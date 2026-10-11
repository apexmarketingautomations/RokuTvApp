#!/usr/bin/env python3
"""Explicit, model-guarded local Roku deployment and secret-free diagnostics."""
import argparse
import getpass
import importlib.util
import ipaddress
import json
import math
import os
from pathlib import Path
import re
import socket
import stat
import sys
import time
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MODEL = "H530X"
MAX_RESPONSE = 8 * 1024 * 1024
KEYS = {"Home", "Back", "Up", "Down", "Left", "Right", "Select", "Play", "Rev", "Fwd", "InstantReplay", "Info"}


def _xml(payload):
    if len(payload) > MAX_RESPONSE or re.search(br"<!\s*(?:DOCTYPE|ENTITY)", payload, re.I):
        raise ValueError("Unsafe or oversized device XML")
    try:
        return ET.fromstring(payload)
    except ET.ParseError:
        raise ValueError("Device did not return valid Roku XML") from None


def _number(text):
    if not text or len(str(text)) > 40 or not re.fullmatch(r"-?\d+(?:\.\d+)?(?:\s*(?:ms|s|bps|bytes|KiB|%))?", str(text).strip()):
        return None
    value = float(re.match(r"-?\d+(?:\.\d+)?", str(text).strip()).group())
    if not math.isfinite(value) or abs(value) > 10**15:
        return None
    return int(value) if value.is_integer() else value


def _code(text):
    return text if text and re.fullmatch(r"[A-Za-z0-9_.+ -]{1,40}", text) else None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Device HTTP redirects are refused")


class Transport:
    def __init__(self, host):
        self.host = host

    def request(self, port, path, data=None, headers=None, password=None):
        base = "http://" + self.host + ":" + str(port)
        handlers = [urllib.request.ProxyHandler({}), NoRedirect()]
        request = urllib.request.Request(base + path, data=data, headers=headers or {})
        if password is not None:
            manager = urllib.request.HTTPPasswordMgrWithDefaultRealm()
            manager.add_password(None, base, "rokudev", password)
            digest = urllib.request.HTTPDigestAuthHandler(manager)
            if data is not None:
                # Roku rejects the first unauthenticated POST before consuming
                # a large ZIP, causing a broken pipe before urllib sees its 401.
                # Obtain a challenge without a body, then authenticate the POST.
                probe = urllib.request.build_opener(*handlers)
                challenge = None
                try:
                    with probe.open(base + "/", timeout=15):
                        pass
                except urllib.error.HTTPError as error:
                    if error.code != 401:
                        raise
                    challenge = error.headers.get("WWW-Authenticate", "")
                    error.close()
                if not challenge or not challenge.lower().startswith("digest "):
                    raise ValueError("Installer did not offer Digest authentication")
                fields = urllib.request.parse_keqv_list(urllib.request.parse_http_list(challenge[7:]))
                authorization = digest.get_authorization(request, fields)
                if not authorization:
                    raise ValueError("Installer Digest challenge is unsupported")
                request.add_unredirected_header("Authorization", "Digest " + authorization)
            handlers.append(digest)
        opener = urllib.request.build_opener(*handlers)
        with opener.open(request, timeout=15) as response:
            payload = response.read(MAX_RESPONSE + 1)
        if len(payload) > MAX_RESPONSE:
            raise ValueError("Device response exceeds 8 MiB")
        return payload


def _multipart(fields, archive=None):
    boundary = "apex-" + uuid.uuid4().hex
    parts = []
    for key, value in fields.items():
        parts.append(("--" + boundary + '\r\nContent-Disposition: form-data; name="' + key + '"\r\n\r\n' + value + "\r\n").encode())
    if archive is not None:
        parts.append(("--" + boundary + '\r\nContent-Disposition: form-data; name="archive"; filename="apex-after-dark-roku.zip"\r\nContent-Type: application/zip\r\n\r\n').encode())
        parts.extend([archive, b"\r\n"])
    parts.append(("--" + boundary + "--\r\n").encode())
    return b"".join(parts), {"Content-Type": "multipart/form-data; boundary=" + boundary}


def _private_path(path, directory, root):
    lexical_root = Path(os.path.abspath(root))
    root = lexical_root.resolve()
    path = Path(os.path.abspath(path))
    if path.is_relative_to(lexical_root):
        path = root / path.relative_to(lexical_root)
    base = root / directory
    if not path.is_relative_to(base) or path == base:
        raise ValueError("File must be inside the repository's " + directory + " directory")
    for part in [path, *path.parents]:
        if part == root:
            break
        if part.is_symlink():
            raise ValueError("Private paths cannot contain symlinks")
    return path


def read_password(path=None, root=ROOT):
    if path is not None:
        path = _private_path(path, ".private", root)
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
        with os.fdopen(descriptor) as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600 or info.st_uid != os.getuid():
                raise ValueError("Password file must be owned by you and have mode 600")
            password = stream.read(4097).rstrip("\r\n")
    elif "ROKU_DEV_PASSWORD" in os.environ:
        password = os.environ["ROKU_DEV_PASSWORD"]
    elif sys.stdin.isatty():
        password = getpass.getpass("Roku developer password: ")
    else:
        raise ValueError("Use an interactive password prompt, ROKU_DEV_PASSWORD, or --password-file")
    if not password or len(password) > 4096 or "\n" in password or "\r" in password:
        raise ValueError("Developer password is empty or invalid")
    return password


def _save_private(path, content, root=ROOT):
    path = _private_path(path, "evidence/private", root)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        os.fchmod(stream.fileno(), 0o600)
        stream.write(content)


def sanitize_log(line):
    """Drop arbitrary log text: regex redaction cannot guarantee credential removal."""
    if line.startswith("APEX_EVENT "):
        try:
            value = json.loads(line[len("APEX_EVENT "):])
        except (ValueError, TypeError):
            return None
        if not isinstance(value, dict):
            return None
        enums = {
            "event": {"startup", "navigation", "playback", "guide", "catalog", "request", "error", "hardware", "focus", "shutdown", "memory", "launch", "screen", "play_requested", "player_state", "playback_position", "player_closed", "segment_download"},
            "screen": {"home", "movies", "tv", "series", "live", "search", "settings", "detail", "player", "guide", "login", "Home", "Movies", "TV Shows", "Live TV", "Favorites", "Guide", "Search", "Settings"},
            "state": {"idle", "buffering", "playing", "paused", "stopped", "finished", "error", "loading", "ready"},
            "kind": {"movie", "series", "episode", "live", "vod"},
            "error_category": {"http", "drm", "mediaerror", "mediaplayer"},
            "model": {MODEL, "H000X"},
        }
        result = {}
        for key, options in enums.items():
            if isinstance(value.get(key), str) and value[key] in options:
                result[key] = value[key]
        for key in ("position", "duration", "elapsed_ms", "error_code", "request_id", "count", "ui_width", "ui_height", "status", "sequence", "segment_type", "bitrate", "width", "height", "bytes"):
            if type(value.get(key)) in (int, float) and abs(value[key]) <= 10**15 and math.isfinite(value[key]):
                result[key] = value[key]
        for key in ("error_detail_code", "drm_error_code"):
            if type(value.get(key)) is int and abs(value[key]) <= 10**15:
                result[key] = value[key]
        if type(value.get("has_more")) is bool:
            result["has_more"] = value["has_more"]
        if isinstance(value.get("build"), str) and re.fullmatch(r"[0-9.]{1,24}", value["build"]):
            result["build"] = value["build"]
        return result if "event" in result else None
    category = re.search(r"\b(compile|runtime) error (&h[0-9a-fA-F]+)", line)
    location = re.search(r"pkg:/(?:source|components)/[A-Za-z0-9_./-]+\.brs\(\d+\)", line)
    if category:
        result = {"event": "brightscript_error", "category": category[1], "code": category[2]}
        if location:
            result["location"] = location[0]
        return result
    return None


class Device:
    def __init__(self, host, transport=None):
        try:
            address = ipaddress.IPv4Address(host)
        except ipaddress.AddressValueError:
            raise ValueError("Target must be an explicit private IPv4 address") from None
        if not any(address in ipaddress.IPv4Network(network) for network in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")):
            raise ValueError("Target must be an explicit private IPv4 address")
        self.host = str(address)
        self.transport = transport or Transport(self.host)

    def guard(self):
        root = _xml(self.transport.request(8060, "/query/device-info"))
        if root.tag != "device-info" or root.findtext("model-number") != MODEL or root.findtext("is-tv") == "false":
            raise ValueError("Target identity mismatch; only the Philips H530X Roku TV is allowed")
        return root

    def info(self):
        root = self.guard()
        result = {"model": MODEL, "evidence_type": "reported_device_capabilities"}
        for tag, key in (("software-version", "os_version"), ("software-build", "os_build"), ("ui-resolution", "ui_resolution")):
            value = _code(root.findtext(tag))
            if value is not None:
                result[key] = value
        if root.findtext("developer-enabled") in {"true", "false"}:
            result["developer_enabled"] = root.findtext("developer-enabled") == "true"
        return result

    def media(self):
        self.guard()
        root = _xml(self.transport.request(8060, "/query/media-player"))
        if root.tag != "player":
            raise ValueError("Unexpected media-player response")
        result = {"evidence_type": "player_telemetry_not_frame_verification"}
        if root.get("state") in {"play", "pause", "stop", "buffer", "close", "open", "none"}:
            result["state"] = root.get("state")
        if root.get("error") in {"true", "false"}:
            result["error"] = root.get("error") == "true"
        for tag in ("position", "duration", "runtime"):
            number = _number(root.findtext(tag))
            if number is not None:
                result[tag + "_ms"] = number
        if root.findtext("is_live") in {"true", "false"}:
            result["is_live"] = root.findtext("is_live") == "true"
        format_node = root.find("format")
        if format_node is not None:
            result["format"] = {key: _code(format_node.get(key)) for key in ("audio", "video", "video_res", "container", "drm") if _code(format_node.get(key)) is not None}
        return result

    def perf(self):
        self.guard()
        root = _xml(self.transport.request(8060, "/query/chanperf"))
        if root.tag != "chanperf" or root.findtext("plugin/id") != "dev" or root.findtext("status") != "OK":
            raise ValueError("Performance data is unavailable for the sideloaded app")
        result = {"evidence_type": "resource_telemetry", "cpu_percent": {}, "memory_bytes": {}}
        for source, destination, keys in (("cpu-percent", "cpu_percent", ("user", "sys")),
                                          ("memory", "memory_bytes", ("used", "res", "anon", "swap", "file", "shared"))):
            for key in keys:
                value = _number(root.findtext("plugin/" + source + "/" + key))
                if value is not None:
                    result[destination][key] = value
        return result

    def key(self, key):
        if key not in KEYS:
            raise ValueError("Unsupported key; only navigation/playback keys are allowed")
        self.guard()
        self.transport.request(8060, "/keypress/" + key, data=b"")
        return {"status": "key_sent", "key": key}

    def launch(self):
        self.guard()
        self.transport.request(8060, "/launch/dev", data=b"")
        return {"status": "launch_requested", "app": "dev"}

    def install(self, archive, password):
        specification = importlib.util.spec_from_file_location("apex_package", Path(__file__).with_name("package.py"))
        module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(module)
        checksum = module.validate_package(archive)
        self.guard()
        body, headers = _multipart({"mysubmit": "Install"}, Path(archive).read_bytes())
        response = self.transport.request(80, "/plugin_install", data=body, headers=headers, password=password).decode("utf-8", "replace")
        if re.search(r"(?:Install|Application)\s+(?:Success|Installed)", response, re.I):
            status = "installed"
        elif re.search(r"Compilation\s+Failed|Install\s+Failure", response, re.I):
            status = "failed"
        elif "identical" in response.lower():
            status = "identical_package_already_installed"
        else:
            status = "unverified_installer_response"
        return {"status": status, "sha256": checksum, "note": "Installation does not verify launch, playback, or account access"}

    def screenshot(self, output, password, root=ROOT):
        _private_path(output, "evidence/private", root)
        self.guard()
        body, headers = _multipart({"mysubmit": "Screenshot"})
        response = self.transport.request(80, "/plugin_inspect", data=body, headers=headers, password=password)
        match = re.search(br'["\'](/pkgs/dev\.(?:png|jpg))["\']', response)
        path = match[1].decode() if match else "/pkgs/dev.jpg"
        content = self.transport.request(80, path, password=password)
        if not content.startswith((b"\x89PNG\r\n\x1a\n", b"\xff\xd8\xff")):
            raise ValueError("Screenshot endpoint did not return PNG/JPEG data")
        _save_private(output, content, root)
        return {"status": "saved", "path": str(output), "evidence_type": "ui_only_excludes_playback"}

    def logs(self, seconds):
        if not 1 <= seconds <= 60:
            raise ValueError("Log duration must be between 1 and 60 seconds")
        self.guard()
        deadline = time.monotonic() + seconds
        records, received, omitted, pending = [], 0, 0, b""
        with socket.create_connection((self.host, 8085), timeout=5) as stream:
            stream.settimeout(0.5)
            while time.monotonic() < deadline:
                try:
                    chunk = stream.recv(8192)
                except socket.timeout:
                    continue
                if not chunk:
                    break
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    received += 1
                    value = sanitize_log(line.decode("utf-8", "replace").strip())
                    if value and len(records) < 5000:
                        records.append(value)
                    else:
                        omitted += 1
                if len(pending) > 65536:
                    pending = b""
                    omitted += 1
        return {"evidence_type": "filtered_runtime_telemetry", "lines_received": received, "lines_omitted": omitted, "records": records}


class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        # argparse normally repeats invalid argument values, which may be secrets.
        self.exit(2, "Invalid command arguments. Run --help; never put passwords on the command line.\n")


def main():
    parser = SafeArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, help="Explicit private IPv4; H530X identity is verified before every command")
    subcommands = parser.add_subparsers(dest="command", required=True)
    for command in ("info", "media", "perf", "launch"):
        subcommands.add_parser(command)
    key = subcommands.add_parser("key")
    key.add_argument("key", choices=sorted(KEYS))
    install = subcommands.add_parser("install", help="Replaces the one sideloaded app")
    install.add_argument("archive", type=Path, nargs="?", default=ROOT / "dist/apex-after-dark-roku.zip")
    install.add_argument("--password-file", type=Path)
    screenshot = subcommands.add_parser("screenshot", help="Private UI screenshot; excludes video playback")
    screenshot.add_argument("--output", required=True, type=Path)
    screenshot.add_argument("--password-file", type=Path)
    logs = subcommands.add_parser("logs", help="Strictly filtered logs; unknown raw lines are omitted")
    logs.add_argument("--seconds", type=int, default=10)
    logs.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        device = Device(args.host)
        if args.command == "install":
            result = device.install(args.archive, read_password(args.password_file))
        elif args.command == "screenshot":
            result = device.screenshot(args.output, read_password(args.password_file))
        elif args.command == "key":
            result = device.key(args.key)
        elif args.command == "logs":
            result = device.logs(args.seconds)
            if args.output:
                _save_private(args.output, (json.dumps(result, indent=2) + "\n").encode())
        else:
            result = getattr(device, args.command)()
        print(json.dumps(result, indent=2))
        return 1 if result.get("status") in {"failed", "unverified_installer_response"} else 0
    except urllib.error.HTTPError as error:
        print(json.dumps({"error": "Device HTTP request failed", "http_status": error.code}), file=sys.stderr)
    except (urllib.error.URLError, socket.timeout, OSError):
        print(json.dumps({"error": "Local device connection or file operation failed"}), file=sys.stderr)
    except ValueError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
