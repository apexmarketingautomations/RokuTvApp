import {spawnSync} from 'node:child_process';
import {existsSync} from 'node:fs';
const suites = [
  ['src/source/Navigation.brs', 'tests/navigation.brs'],
  ['src/source/Core.brs', 'src/components/ApiTask.brs', 'tests/core.brs'],
  ['src/source/Navigation.brs', 'src/components/ApexScene.brs', 'tests/scene.brs']
];
let failed = false;
for (const files of suites) {
  if (!files.every(existsSync)) { console.error('Missing suite:', files.join(' ')); failed = true; continue; }
  const r = spawnSync(process.execPath, ['node_modules/brs/bin/cli.js', '--root', 'tests', ...files], {encoding:'utf8'});
  process.stdout.write(r.stdout || ''); process.stderr.write(r.stderr || '');
  if (r.status !== 0 || !/PASS/.test(r.stdout || '') || /FAIL|error|not a function|Attempting/i.test((r.stdout || '') + (r.stderr || ''))) failed = true;
}
if (existsSync('tests/test_tools.py')) {
  const r = spawnSync('python3', ['-m','unittest','discover','-s','tests','-p','test_*.py'], {stdio:'inherit'});
  if (r.status !== 0) failed = true;
}
process.exitCode = failed ? 1 : 0;
