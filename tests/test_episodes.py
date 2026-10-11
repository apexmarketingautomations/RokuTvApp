import unittest

from api_test_support import run_api_suite


class EpisodeTests(unittest.TestCase):
    def test_episode_search_preserves_season_and_page_without_network(self):
        run_api_suite("episodes.brs")


if __name__ == "__main__":
    unittest.main()
