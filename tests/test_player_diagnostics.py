import json
from pathlib import Path
import shutil
import subprocess
import unittest

from test_tools import load_tool


ROOT = Path(__file__).resolve().parents[1]


class PlayerDiagnosticsTests(unittest.TestCase):
    def test_actual_player_state_logs_export_only_safe_native_error_details(self):
        result = subprocess.run(
            [shutil.which("node"), str(ROOT / "node_modules/brs/bin/cli.js"),
             "--root", str(ROOT / "tests"), str(ROOT / "src/source/Navigation.brs"),
             str(ROOT / "src/components/ApexScene.brs"),
             str(ROOT / "tests/player_diagnostics.brs")],
            cwd=ROOT, capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS player diagnostics", result.stdout)
        self.assertNotIn("private", result.stdout)
        self.assertNotIn("secret", result.stdout)
        lines = [line for line in result.stdout.splitlines() if line.startswith("APEX_EVENT ")]
        self.assertEqual(len(lines), 7, result.stdout)
        tool = load_tool("roku")
        for line, category in zip(lines[:4], ["http", "drm", "mediaerror", "mediaplayer"]):
            expected = {"event": "player_state", "state": "error", "error_code": -6,
                        "error_category": category, "error_detail_code": -1004,
                        "drm_error_code": 0}
            self.assertEqual(json.loads(line.removeprefix("APEX_EVENT ")), expected)
            self.assertEqual(tool.sanitize_log(line), expected)
        self.assertEqual(json.loads(lines[4].removeprefix("APEX_EVENT ")),
                         {"event": "player_state", "state": "error", "error_code": -6})
        self.assertEqual(json.loads(lines[5].removeprefix("APEX_EVENT ")),
                         {"event": "player_state", "state": "playing", "error_code": 0})
        expected = {"event": "segment_download", "status": 961, "sequence": 22,
                    "position": 176, "segment_type": 2, "bitrate": 7201340,
                    "width": 1920, "height": 1036, "bytes": 0, "elapsed_ms": 400}
        self.assertEqual(json.loads(lines[6].removeprefix("APEX_EVENT ")), expected)
        self.assertEqual(tool.sanitize_log(lines[6]), expected)

    def test_log_filter_rejects_untrusted_error_details(self):
        tool = load_tool("roku")
        for fields in (
            {"error_category": "https://private.test/secret", "error_detail_code": "secret", "drm_error_code": "secret"},
            {"error_category": {}, "error_detail_code": 10**16, "drm_error_code": True},
        ):
            line = "APEX_EVENT " + json.dumps({"event": "player_state", **fields})
            self.assertEqual(tool.sanitize_log(line), {"event": "player_state"})


if __name__ == "__main__":
    unittest.main()
