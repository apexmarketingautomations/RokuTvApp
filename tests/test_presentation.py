import unittest

from api_test_support import run_api_suite


class PresentationTests(unittest.TestCase):
    def test_playback_and_history_preserve_artwork_with_current_transport(self):
        run_api_suite("presentation.brs")


if __name__ == "__main__":
    unittest.main()
