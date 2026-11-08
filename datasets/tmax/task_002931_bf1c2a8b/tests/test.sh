#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
DEFS = HOME / 'pipeline_defs'
ANALYZER = HOME / 'pipeline_analyzer.py'
CYCLE_REPORT = HOME / 'cycle_report.txt'
INVALID_REPORT = HOME / 'invalid_versions.txt'
USER_TESTS = HOME / 'test_analyzer.py'


def test_cycle_report_contents():
    assert CYCLE_REPORT.is_file(), f"File {CYCLE_REPORT} does not exist. The cycle report was not created."
    content = CYCLE_REPORT.read_text().strip()
    expected_cycle = "task_A -> task_B -> task_C -> task_A"
    assert content == expected_cycle, f"Cycle report content is incorrect. Expected '{expected_cycle}', but got '{content}'."


def test_invalid_versions_file_exists():
    assert INVALID_REPORT.is_file(), f"File {INVALID_REPORT} does not exist."


def test_pipeline_analyzer_exists():
    assert ANALYZER.is_file(), f"File {ANALYZER} does not exist."
    assert not ANALYZER.is_symlink(), f"{ANALYZER} must be a regular submitted Python file."
    ast.parse(ANALYZER.read_text(), filename=str(ANALYZER))


def test_test_analyzer_exists_and_passes():
    assert USER_TESTS.is_file(), f"File {USER_TESTS} does not exist."

    source = USER_TESTS.read_text()
    tree = ast.parse(source, filename=str(USER_TESTS))
    tests = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name.startswith('test_')]
    assert tests, f"{USER_TESTS} does not contain any pytest test functions."
    assert any(any(isinstance(x, ast.Assert) for x in ast.walk(test)) for test in tests), \
        f"{USER_TESTS} does not contain an assertion in a test."
    assert re.search(r'requests|registry', source, re.I) and re.search(r'get', source, re.I), \
        f"{USER_TESTS} does not target the registry requests.get call."
    assert re.search(r'monkeypatch|mock|patch', source, re.I), \
        f"{USER_TESTS} does not appear to mock requests.get."

    result = subprocess.run(
        ['pytest', str(USER_TESTS)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"pytest on {USER_TESTS} failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def write_definitions(definitions):
    shutil.rmtree(DEFS)
    DEFS.mkdir(parents=True)
    for index, definition in enumerate(definitions):
        path = DEFS / f'{index:02d}_{definition["name"]}.json'
        path.write_text(json.dumps(definition))


def run_analyzer(registry):
    mock_dir = Path('/tmp/verifier_registry_mock')
    shutil.rmtree(mock_dir, ignore_errors=True)
    mock_dir.mkdir()
    registry_file = mock_dir / 'registry.json'
    calls_file = mock_dir / 'calls.txt'
    registry_file.write_text(json.dumps(registry))

    (mock_dir / 'sitecustomize.py').write_text(r'''
import json
import os
from pathlib import Path
from urllib.parse import unquote, urlparse
import requests

_registry = json.loads(Path(os.environ['VERIFIER_REGISTRY_FILE']).read_text())
_calls = Path(os.environ['VERIFIER_CALLS_FILE'])

class FakeResponse:
    status_code = 200
    ok = True
    def __init__(self, versions):
        self._payload = {'versions': versions}
        self.text = json.dumps(self._payload)
        self.content = self.text.encode()
    def json(self):
        return self._payload
    def raise_for_status(self):
        return None

def fake_get(url, *args, **kwargs):
    parsed = urlparse(url)
    prefix = '/api/tools/'
    if parsed.scheme != 'http' or parsed.netloc != 'registry.internal' or not parsed.path.startswith(prefix):
        raise AssertionError('Unexpected registry URL: ' + str(url))
    tool = unquote(parsed.path[len(prefix):])
    if not tool or '/' in tool or tool not in _registry:
        raise AssertionError('Unexpected tool request: ' + tool)
    with _calls.open('a') as handle:
        handle.write(tool + '\n')
    return FakeResponse(_registry[tool])

requests.get = fake_get
''')

    for output in (CYCLE_REPORT, INVALID_REPORT):
        try:
            output.unlink()
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['PYTHONPATH'] = str(mock_dir)
    env['VERIFIER_REGISTRY_FILE'] = str(registry_file)
    env['VERIFIER_CALLS_FILE'] = str(calls_file)
    result = subprocess.run(
        ['python3', str(ANALYZER)],
        cwd=str(HOME),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Analyzer execution failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert CYCLE_REPORT.is_file(), 'Analyzer did not create cycle_report.txt when executed.'
    assert INVALID_REPORT.is_file(), 'Analyzer did not create invalid_versions.txt when executed.'

    calls = calls_file.read_text().splitlines() if calls_file.exists() else []
    assert set(calls) == set(registry), f"Expected registry calls for {sorted(registry)}, got {calls}."
    assert all(calls.count(tool) >= 1 for tool in registry)


def test_analyzer_behavior_with_derived_registry_answers():
    backup_root = Path(tempfile.mkdtemp(prefix='pipeline-verifier-backup-'))
    shutil.copytree(DEFS, backup_root / 'pipeline_defs')
    saved_outputs = {}
    for output in (CYCLE_REPORT, INVALID_REPORT):
        saved_outputs[output] = output.read_bytes() if output.exists() else None

    try:
        write_definitions([
            {'name': 'gamma', 'depends_on': ['alpha'], 'requires': {'also_bad': '~=1.4.5'}},
            {'name': 'alpha', 'depends_on': ['beta'], 'requires': {'bad_highest': '>=1.0, <2.0'}},
            {'name': 'beta', 'depends_on': ['gamma'], 'requires': {'good': '>=2.0, !=2.5.*, <3.0'}},
            {'name': 'standalone', 'depends_on': [], 'requires': {}},
        ])
        run_analyzer({
            'bad_highest': ['2.0.0', '1.5.0'],
            'good': ['2.6.0', '2.5.4', '1.0.0'],
            'also_bad': ['1.4.6', '1.5.0'],
        })
        assert CYCLE_REPORT.read_text().strip() == 'alpha -> beta -> gamma -> alpha'
        assert INVALID_REPORT.read_text().splitlines() == ['also_bad', 'bad_highest']

        write_definitions([
            {'name': 'root', 'depends_on': ['left', 'right'], 'requires': {'semantic': '>=10.0.0'}},
            {'name': 'left', 'depends_on': [], 'requires': {'omega': '<10.0.0'}},
            {'name': 'right', 'depends_on': [], 'requires': {}},
        ])
        run_analyzer({
            'semantic': ['10.0.0', '2.0.0'],
            'omega': ['9.0.0', '10.0.0'],
        })
        assert CYCLE_REPORT.read_text() == '', 'Acyclic definitions must produce an empty cycle report.'
        assert INVALID_REPORT.read_text().splitlines() == ['omega']
    finally:
        shutil.rmtree(DEFS, ignore_errors=True)
        shutil.copytree(backup_root / 'pipeline_defs', DEFS)
        for output, data in saved_outputs.items():
            if data is None:
                try:
                    output.unlink()
                except FileNotFoundError:
                    pass
            else:
                output.write_bytes(data)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
