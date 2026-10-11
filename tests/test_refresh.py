"""Exercise real worker refresh routing; adapt unavailable native URL escaping."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from api_test_support import ROOT


class RefreshTests(unittest.TestCase):
    def test_refresh_replaces_inventory_atomically_and_preserves_private_state(self):
        source = (ROOT / "src/components/ApiTask.brs").read_text()
        source, count = re.subn(r"(?m)^function ApiHttp\(", "function ApiHttpNative(", source)
        self.assertEqual(count, 1)
        # Fixture credentials contain only letters. Keep real route construction;
        # brs cannot instantiate the native object's escape method.
        source = source.replace('escape = createObject("roUrlTransfer")', 'escape = TestUrlEncoder()')
        with tempfile.TemporaryDirectory() as temporary:
            worker = Path(temporary) / "ApiTask.brs"
            worker.write_text(source)
            result = subprocess.run(
                [shutil.which("node"), str(ROOT / "node_modules/brs/bin/cli.js"),
                 "--root", str(ROOT / "tests"), str(ROOT / "src/source/Core.brs"),
                 str(worker), str(ROOT / "tests/refresh.brs")],
                cwd=ROOT, capture_output=True, text=True,
            )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("PASS refresh", output)
        self.assertNotRegex(output, r"(?i)\bFAIL\b|\berror\b|not a function|Attempting")


if __name__ == "__main__":
    unittest.main()
