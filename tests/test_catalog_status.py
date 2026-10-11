from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CatalogStatusTests(unittest.TestCase):
    def test_status_preserves_result_counts_and_loaded_tv_scope(self):
        source = (ROOT / "src/components/ApexScene.brs").read_text()
        source, count = re.subn(r"(?m)^sub renderRows\(\)", "sub renderRowsNative()", source)
        self.assertEqual(count, 1)
        with tempfile.TemporaryDirectory() as temporary:
            scene = Path(temporary) / "ApexScene.brs"
            scene.write_text(source)
            result = subprocess.run(
                [shutil.which("node"), str(ROOT / "node_modules/brs/bin/cli.js"),
                 "--root", str(ROOT / "tests"), str(ROOT / "src/source/Navigation.brs"),
                 str(scene), str(ROOT / "tests/catalog_status.brs")],
                cwd=ROOT, capture_output=True, text=True,
            )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("PASS catalog status", output)
        self.assertNotRegex(output, r"(?i)\bFAIL\b|not a function|Attempting")


if __name__ == "__main__":
    unittest.main()
