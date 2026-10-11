import unittest

from api_test_support import run_api_suite


class MetadataTests(unittest.TestCase):
    def test_metadata_recovery(self):
        run_api_suite("metadata.brs")


if __name__ == "__main__":
    unittest.main()
