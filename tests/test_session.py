import unittest

from api_test_support import run_api_suite


class SessionTests(unittest.TestCase):
    def test_saved_account_survives_provider_failure_and_loads_live_lazily(self):
        run_api_suite("session.brs")


if __name__ == "__main__":
    unittest.main()
