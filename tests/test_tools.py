"""Offline contracts for release packaging and guarded Roku diagnostics."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def load_tool(name):
    path = ROOT / "scripts" / (name + ".py")
    if not path.exists():
        return None
    spec = importlib.util.spec_from_file_location("apex_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool("package")
        self.assertIsNotNone(self.tool, "release packager has not been implemented")
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stage = self.root / "staging"
        self.stage.mkdir()
        self.write("manifest", "title=Apex After Dark\nmajor_version=1\n")
        self.write("source/main.brs", 'sub Main()\n print "ready"\nend sub\n')
        self.write("components/Scene.xml", '<component name="Scene" extends="Scene"/>')
        self.write("images/logo.png", b"\x89PNG\r\n\x1a\n")

    def write(self, name, data):
        path = self.stage / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else data.encode())
        return path

    def test_package_is_reproducible_and_excludes_non_runtime_files(self):
        self.write(".private/credentials.json", '{"password":"never-ship-this"}')
        self.write("source/.env", "SECRET=never-ship-this")
        self.write("source/debug.log", "never-ship-this")
        self.write("components/Scene.brs.map", "never-ship-this")
        self.write("README.md", "never-ship-this")
        output = self.root / "dist/app.zip"
        first = self.tool.build_package(self.stage, output)
        original = output.read_bytes()
        os.utime(self.stage / "source/main.brs", (1900000000, 1900000000))
        second = self.tool.build_package(self.stage, output)
        self.assertEqual(original, output.read_bytes())
        self.assertEqual(first["sha256"], second["sha256"])
        self.assertEqual(hashlib.sha256(original).hexdigest(), first["sha256"])
        self.assertEqual(output.with_suffix(".zip.sha256").read_text(), first["sha256"] + "  app.zip\n")
        with zipfile.ZipFile(output) as archive:
            self.assertEqual(archive.namelist(), ["components/Scene.xml", "images/logo.png", "manifest", "source/main.brs"])
            self.assertTrue(all(x.date_time == (1980, 1, 1, 0, 0, 0) for x in archive.infolist()))
            self.assertNotIn(b"never-ship-this", b"".join(archive.read(x) for x in archive.namelist()))

    def test_rejects_symlinked_runtime_input(self):
        secret = self.root / "private.brs"
        secret.write_text('print "credential"')
        (self.stage / "source/linked.brs").symlink_to(secret)
        with self.assertRaises(ValueError):
            self.tool.build_package(self.stage, self.root / "app.zip")

    def test_rejects_obvious_hardcoded_credentials_without_echoing_them(self):
        self.write("source/main.brs", 'url = "https://stream.example/live/test-user/test-password/100.ts"')
        with self.assertRaises(ValueError) as caught:
            self.tool.build_package(self.stage, self.root / "app.zip")
        self.assertNotIn("test-password", str(caught.exception))

    def test_safe_url_validation_regex_is_not_a_literal_credential(self):
        self.write("source/main.brs", 'if createObject("roRegex", "^https://[^/]*@", "i").isMatch(url) then return ""')
        output = self.root / "app.zip"
        self.tool.build_package(self.stage, output)
        self.assertTrue(output.is_file())
        self.write("source/main.brs", 'url = "https://account:private-password@provider.example/path"')
        with self.assertRaises(ValueError):
            self.tool.build_package(self.stage, output)

    def test_failed_validation_removes_compiler_zip_and_stale_checksum(self):
        output = self.root / "app.zip"
        output.write_bytes(b"unvalidated compiler archive")
        checksum = output.with_suffix(".zip.sha256")
        checksum.write_text("stale-checksum")
        self.write("source/main.brs", 'password = "test-password"')
        with self.assertRaises(ValueError):
            self.tool.build_package(self.stage, output)
        self.assertFalse(output.exists())
        self.assertFalse(checksum.exists())

    def test_requires_manifest_and_rejects_archive_traversal_before_install(self):
        (self.stage / "manifest").unlink()
        with self.assertRaises(ValueError):
            self.tool.build_package(self.stage, self.root / "app.zip")
        archive_path = self.root / "hostile.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            archive.writestr("manifest", "title=test")
            archive.writestr("../.private/password", "secret")
        with self.assertRaises(ValueError):
            self.tool.validate_package(archive_path)


TARGET_XML = b"""<device-info><model-number>H530X</model-number><is-tv>true</is-tv>
<software-version>15.3.4</software-version><software-build>2303</software-build>
<developer-enabled>false</developer-enabled>
<ui-resolution>720p</ui-resolution><serial-number>private-serial</serial-number>
<friendly-device-name>private-room</friendly-device-name></device-info>"""


class FakeTransport:
    """Only the HTTP boundary is replaced; parsing, guarding, filtering run normally."""
    def __init__(self, device=TARGET_XML, responses=None):
        self.device = device
        self.responses = responses or {}
        self.calls = []

    def request(self, port, path, data=None, headers=None, password=None):
        self.calls.append((port, path, data, password))
        if path == "/query/device-info":
            return self.device
        if path in self.responses:
            return self.responses[path]
        raise AssertionError("Unexpected test HTTP request")


class RokuTests(unittest.TestCase):
    def test_actual_app_telemetry_survives_filter(self):
        tool = load_tool("roku")
        for event in ("launch", "screen", "play_requested", "player_state", "playback_position", "player_closed"):
            record = tool.sanitize_log('APEX_EVENT ' + json.dumps({"event": event, "screen":"TV Shows", "position":42, "password":"private"}))
            self.assertIsNotNone(record, event)
            self.assertEqual(record["event"], event)
            self.assertEqual(record["screen"], "TV Shows")
            self.assertNotIn("password", record)

    def setUp(self):
        self.tool = load_tool("roku")
        self.assertIsNotNone(self.tool, "Roku tool has not been implemented")

    def test_refuses_other_devices_before_a_mutating_request(self):
        for model in (b"Fire TV Stick", b"4850X", b"H000X"):
            transport = FakeTransport(TARGET_XML.replace(b"H530X", model))
            device = self.tool.Device("192.168.0.110", transport=transport)
            with self.assertRaises(ValueError):
                device.key("Home")
            self.assertEqual([x[1] for x in transport.calls], ["/query/device-info"])

    def test_private_ipv4_target_only_and_no_arbitrary_ecp_path(self):
        for host in ("amazon-fire-tv.local", "https://192.168.0.110", "8.8.8.8", "127.0.0.1", "192.168.0.110:8060"):
            with self.assertRaises(ValueError):
                self.tool.Device(host)
        transport = FakeTransport(responses={"/keypress/Home": b""})
        device = self.tool.Device("192.168.0.110", transport=transport)
        with self.assertRaises(ValueError):
            device.key("Home/../../launch/other")
        result = device.key("Home")
        self.assertEqual(result["key"], "Home")
        self.assertEqual([x[1] for x in transport.calls], ["/query/device-info", "/keypress/Home"])

    def test_evidence_filters_identity_and_media_urls(self):
        media = b'''<player error="false" state="play"><plugin name="Secret account" id="dev"/>
        <format audio="aac" video="h264" video_res="1920x1080" container="hls"/>
        <position>1234 ms</position><duration>8000 ms</duration><is_live>false</is_live>
        <stream_segment url="https://example/live/user/password/stream.ts" bitrate="5000000"/></player>'''
        device = self.tool.Device("192.168.0.110", transport=FakeTransport(responses={"/query/media-player": media}))
        info = device.info()
        self.assertEqual(info["model"], "H530X")
        self.assertFalse(info.get("developer_enabled", True))
        evidence = device.media()
        self.assertEqual(evidence["position_ms"], 1234)
        self.assertEqual(evidence["state"], "play")
        self.assertEqual(evidence["evidence_type"], "player_telemetry_not_frame_verification")
        serialized = json.dumps([info, evidence])
        for secret in ("private-serial", "private-room", "Secret account", "example/live", "password"):
            self.assertNotIn(secret, serialized)

    def test_logs_keep_structured_metrics_and_omit_unstructured_secrets(self):
        lines = [
            'password=actual-secret',
            'https://provider.test/live/account/password/1.ts',
            'APEX_EVENT {"event":"playback","state":"playing","position":12.5,"url":"https://user:secret@host/","token":"another-secret"}',
            'APEX_EVENT {"event":"playback","state":"https://private.example/secret","position":13}',
            'Syntax Error. (compile error &h02) in pkg:/source/main.brs(42)',
        ]
        records = [self.tool.sanitize_log(line) for line in lines]
        self.assertIsNone(records[0])
        self.assertIsNone(records[1])
        self.assertEqual(records[2], {"event": "playback", "state": "playing", "position": 12.5})
        self.assertNotIn("state", records[3])
        self.assertEqual(records[4]["location"], "pkg:/source/main.brs(42)")
        self.assertNotIn("secret", json.dumps(records))

    def test_password_file_must_be_private_and_is_never_printed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / ".private/roku-password"
            path.parent.mkdir()
            path.write_text("known-password\n")
            path.chmod(0o644)
            with patch.dict(os.environ, {}, clear=True):
                with self.assertRaises(ValueError):
                    self.tool.read_password(path, root=root)
                path.chmod(0o600)
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    self.assertEqual(self.tool.read_password(path, root=root), "known-password")
                self.assertEqual(output.getvalue(), "")
                outside = root / "outside"
                outside.write_text("known-password")
                outside.chmod(0o600)
                with self.assertRaises(ValueError):
                    self.tool.read_password(outside, root=root)

    def test_install_checks_target_and_reports_only_known_installer_status(self):
        packager = load_tool("package")
        self.assertIsNotNone(packager)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stage = root / "stage"
            stage.mkdir()
            (stage / "manifest").write_text("title=Test\n")
            (stage / "source").mkdir()
            (stage / "source/main.brs").write_text("sub Main()\nend sub\n")
            archive = root / "app.zip"
            packager.build_package(stage, archive)
            transport = FakeTransport(responses={"/plugin_install": b"<html>Install Success. private-debug-secret</html>"})
            device = self.tool.Device("192.168.0.110", transport=transport)
            result = device.install(archive, "not-logged")
            self.assertEqual(result["status"], "installed")
            self.assertEqual([x[1] for x in transport.calls], ["/query/device-info", "/plugin_install"])
            self.assertIn(b"PK", transport.calls[1][2])
            self.assertNotIn("private-debug-secret", json.dumps(result))
            self.assertNotIn("not-logged", json.dumps(result))

    def test_screenshot_is_private_and_cannot_follow_remote_image_links(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            transport = FakeTransport(responses={
                "/plugin_inspect": b'<img src="http://other-device/pk"/><img src="/pkgs/dev.png"/>',
                "/pkgs/dev.png": b"\x89PNG\r\n\x1a\nbytes",
            })
            device = self.tool.Device("192.168.0.110", transport=transport)
            output = root / "evidence/private/ui.png"
            result = device.screenshot(output, "private-password", root=root)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)
            self.assertEqual(result["evidence_type"], "ui_only_excludes_playback")
            self.assertEqual([x[1] for x in transport.calls], ["/query/device-info", "/plugin_inspect", "/pkgs/dev.png"])

    def test_malformed_or_entity_xml_is_rejected(self):
        for payload in (b"bad-xml", b'<!DOCTYPE x [<!ENTITY a "secret">]><device-info>&a;</device-info>'):
            with self.assertRaises(ValueError):
                self.tool.Device("192.168.0.110", transport=FakeTransport(payload)).info()

    def test_performance_keeps_units_and_only_sideloaded_app_metrics(self):
        response = b'''<chanperf><timestamp>1672980398506</timestamp><plugin>
        <cpu-percent><duration-seconds>1.000000</duration-seconds><user>12.2</user><sys>5.5</sys></cpu-percent>
        <memory><used>87785472</used><res>87785472</res><anon>24027136</anon><swap>0</swap><file>24727552</file><shared>39030784</shared></memory>
        <id>dev</id><unsecured><process-id>6861</process-id></unsecured>
        </plugin><status>OK</status></chanperf>'''
        transport = FakeTransport(responses={"/query/chanperf": response})
        result = self.tool.Device("192.168.0.110", transport=transport).perf()
        self.assertEqual(result["cpu_percent"], {"user": 12.2, "sys": 5.5})
        self.assertEqual(result["memory_bytes"]["used"], 87785472)
        self.assertNotIn("process-id", json.dumps(result))
        transport.responses["/query/chanperf"] = response.replace(b"<id>dev</id>", b"<id>12345</id>")
        with self.assertRaises(ValueError):
            self.tool.Device("192.168.0.110", transport=transport).perf()

    def test_invalid_cli_arguments_do_not_echo_possible_secrets(self):
        result = subprocess.run([sys.executable, str(ROOT / "scripts/roku.py"), "--password", "mistyped-secret"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("mistyped-secret", result.stdout + result.stderr)
        result = subprocess.run([sys.executable, str(ROOT / "scripts/roku.py"), "--host", "192.168.0.110", "key", "mistyped-secret"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("mistyped-secret", result.stdout + result.stderr)

    def test_checksum_rejects_tampered_archive_before_any_network_request(self):
        packager = load_tool("package")
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / "app.zip"
            with zipfile.ZipFile(archive, "w") as output:
                output.writestr("manifest", "title=Changed\n")
            archive.with_suffix(".zip.sha256").write_text("0" * 64 + "  app.zip\n")
            transport = FakeTransport()
            with self.assertRaises(ValueError):
                self.tool.Device("192.168.0.110", transport=transport).install(archive, "unused-password")
            self.assertEqual(transport.calls, [])

    def test_private_file_symlinks_and_unbounded_log_values_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / ".private").mkdir()
            actual = root / "actual-password"
            actual.write_text("secret")
            actual.chmod(0o600)
            path = root / ".private/password"
            path.symlink_to(actual)
            with self.assertRaises(ValueError):
                self.tool.read_password(path, root=root)
        value = self.tool.sanitize_log('APEX_EVENT {"event":"playback","position":' + "9" * 400 + '}')
        self.assertEqual(value, {"event": "playback"})

    def test_log_collection_never_returns_raw_console_text(self):
        class FakeSocket:
            def __init__(self):
                self.chunks = iter([b'raw-private-token\nAPEX_EVENT {"event":"startup","build":"1.0.0"}\n', b''])

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def settimeout(self, timeout):
                pass

            def recv(self, size):
                return next(self.chunks)

        transport = FakeTransport()
        device = self.tool.Device("192.168.0.110", transport=transport)
        with patch.object(self.tool.socket, "create_connection", return_value=FakeSocket()):
            result = device.logs(1)
        self.assertEqual(result["records"], [{"event": "startup", "build": "1.0.0"}])
        self.assertEqual(result["lines_omitted"], 1)
        self.assertNotIn("private-token", json.dumps(result))
        self.assertEqual([x[1] for x in transport.calls], ["/query/device-info"])


if __name__ == "__main__":
    unittest.main()
