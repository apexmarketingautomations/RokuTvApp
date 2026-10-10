#!/usr/bin/env python3
"""Build a reproducible Roku ZIP from compiler staging, never the checkout."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MAX_PACKAGE_BYTES = 100 * 1024 * 1024


def runtime_path(name):
    path = PurePosixPath(name)
    if name != path.as_posix() or path.is_absolute() or "\\" in name:
        return False
    if any(part.startswith(".") for part in path.parts):
        return False
    if name == "manifest":
        return True
    if len(path.parts) < 2:
        return False
    extensions = {"source": {".brs"}, "components": {".brs", ".xml"},
                  "images": {".png", ".jpg", ".jpeg", ".webp", ".gif"}}
    return path.suffix.lower() in extensions.get(path.parts[0], set())


def check_content(name, content):
    if name != "manifest" and not name.endswith((".brs", ".xml")):
        return
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError:
        raise ValueError("Runtime text must be UTF-8") from None
    # Detect embedded literal secrets without rejecting code that builds URLs at runtime.
    suspicious = (
        r'https?://[^/\s"<>\[\]\^*(){}]+@',
        r'https?://[^\s"<>]*[?&](?:password|passwd|username|token|api_key|apikey|auth)=[^&\s"<>]+',
        r'https?://[^\s"<>]+/(?:live|movie|series)/[^/\s"<>]+/[^/\s"<>]+/',
        r'(?i)\b(?:password|passwd|api_key|apikey|access_token|refresh_token)\s*[:=]\s*"[^"\n]+"',
        r'(?i)\bBearer\s+[a-zA-Z0-9_.~+/=-]{12,}',
        r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    )
    if any(re.search(pattern, text) for pattern in suspicious):
        raise ValueError("Possible embedded credential in runtime text; package refused")


def validate_package(path):
    """Validate archive contents without extracting them; return its checksum."""
    path = Path(path)
    if path.stat().st_size > MAX_PACKAGE_BYTES:
        raise ValueError("Package exceeds the local 100 MiB safety bound")
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            if "manifest" not in names or len(names) != len(set(names)):
                raise ValueError("Package must contain one manifest and unique entries")
            total = 0
            for member in archive.infolist():
                total += member.file_size
                mode = member.external_attr >> 16
                if not runtime_path(member.filename) or stat.S_ISLNK(mode):
                    raise ValueError("Package contains a non-runtime or unsafe entry")
                if total > MAX_PACKAGE_BYTES or member.flag_bits & 1:
                    raise ValueError("Package is encrypted or exceeds the expansion bound")
                check_content(member.filename, archive.read(member))
    except zipfile.BadZipFile:
        raise ValueError("Invalid Roku ZIP archive") from None
    checksum = hashlib.sha256(path.read_bytes()).hexdigest()
    sidecar = path.with_suffix(path.suffix + ".sha256")
    if sidecar.exists():
        expected = sidecar.read_text().split()
        if not expected or expected[0] != checksum:
            raise ValueError("Package SHA-256 does not match its sidecar")
    return checksum


def build_package(staging, output):
    staging, output = Path(staging), Path(output)
    # bsc may already have written an unvalidated ZIP here. Only our validated
    # atomic replacement is a release artifact; failed builds leave none.
    output.unlink(missing_ok=True)
    output.with_suffix(output.suffix + ".sha256").unlink(missing_ok=True)
    if not staging.is_dir() or staging.is_symlink():
        raise ValueError("Compiler staging is missing or is a symlink; run the compiler first")
    staging = staging.resolve()
    files = []
    for path in sorted(staging.rglob("*")):
        relative = path.relative_to(staging).as_posix()
        if path.is_symlink() and (runtime_path(relative) or relative in {"source", "components", "images", "manifest"}):
            raise ValueError("Symlinked runtime input is not allowed")
        if not path.is_file() or not runtime_path(relative):
            continue
        if any(parent.is_symlink() for parent in path.parents if parent.is_relative_to(staging)):
            raise ValueError("Symlinked runtime input is not allowed")
        content = path.read_bytes()
        check_content(relative, content)
        files.append((relative, content))
    if "manifest" not in {name for name, _ in files}:
        raise ValueError("Compiler staging must contain manifest at its root")
    if sum(len(content) for _, content in files) > MAX_PACKAGE_BYTES:
        raise ValueError("Package exceeds the local 100 MiB safety bound")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".zip", delete=False) as temp:
        temporary = Path(temp.name)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name, content in files:
                entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = (stat.S_IFREG | 0o644) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, content, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        checksum = validate_package(temporary)
        temporary.replace(output)
        output.with_suffix(output.suffix + ".sha256").write_text(checksum + "  " + output.name + "\n")
    finally:
        temporary.unlink(missing_ok=True)
    return {"package": str(output), "sha256": checksum, "files": len(files), "bytes": output.stat().st_size}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staging", type=Path, default=ROOT / "dist/staging")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/apex-after-dark-roku.zip")
    args = parser.parse_args()
    try:
        print(json.dumps(build_package(args.staging, args.output), indent=2))
    except (OSError, ValueError) as error:
        # Error content is ours, never file bodies or credentials.
        parser.exit(1, "Package failed: " + (str(error) if isinstance(error, ValueError) else "filesystem operation failed") + "\n")


if __name__ == "__main__":
    main()
