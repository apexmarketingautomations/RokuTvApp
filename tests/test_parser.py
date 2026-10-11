import itertools
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ParserTests(unittest.TestCase):
    def test_parser_compatibility_and_delimiter_cost(self):
        alphabet = ['a', ',', '"', "'", '\\', '\r']
        corpus = [''.join(chars) for size in range(5)
                  for chars in itertools.product(alphabet, repeat=size)]
        corpus += ['L’été ☕,"épisode, titre",show', '"unterminated, title',
                   'name="escaped\\"quote, value",title',
                   "name='escaped\\'quote, value',title"]
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            for filename in ('parser_compat.m3u', 'parser_compat.json'):
                shutil.copy(ROOT / 'tests/fixtures' / filename, temporary / filename)
            (temporary / 'comma_corpus.json').write_text(json.dumps(corpus))
            result = subprocess.run(
                [shutil.which('node'), str(ROOT / 'node_modules/brs/bin/cli.js'),
                 '--root', str(temporary), str(ROOT / 'src/source/Core.brs'),
                 str(ROOT / 'tests/parser.brs')],
                cwd=ROOT, capture_output=True, text=True,
            )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('PARSER TESTS PASSED', output)
        self.assertFalse(re.search(r'\bFAIL\b|\berror\b|not a function|Attempting',
                                   output, re.IGNORECASE), output)


if __name__ == '__main__':
    unittest.main()
