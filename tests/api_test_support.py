"""Execute real worker logic with only the unavailable HTTP transport replaced."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def run_api_suite(fixture):
    # brs has no roUrlTransfer implementation. Rename only the transport's
    # declaration so the fixture can supply HTTP responses to unchanged callers.
    source = (ROOT / "src/components/ApiTask.brs").read_text()
    source, count = re.subn(r"(?m)^function ApiHttp\(", "function ApiHttpNative(", source)
    if count != 1:
        raise AssertionError("Expected one worker HTTP transport declaration")
    with tempfile.TemporaryDirectory() as temporary:
        worker = Path(temporary) / "ApiTask.brs"
        worker.write_text(source)
        result = subprocess.run(
            [shutil.which("node"), str(ROOT / "node_modules/brs/bin/cli.js"),
             "--root", str(ROOT / "tests"), str(ROOT / "src/source/Core.brs"),
             str(worker), str(ROOT / "tests" / fixture)],
            cwd=ROOT, capture_output=True, text=True,
        )
    output = result.stdout + result.stderr
    if result.returncode != 0 or "PASS" not in output or re.search(
        r"\bFAIL\b|\berror\b|not a function|Attempting", output, re.IGNORECASE
    ):
        raise AssertionError(output)
    return output
