import unittest

from api_test_support import run_api_suite


class PlaybackTests(unittest.TestCase):
    def test_extensionless_stream_resolution_uses_supported_mime_types(self):
        run_api_suite("playback.brs")


if __name__ == "__main__":
    unittest.main()
