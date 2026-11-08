#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import importlib
import importlib.machinery
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

REPO = Path('/home/user/log_parser_accel')


def test_setup_py_fixed():
    """Test that setup.py has been updated to use RustExtension."""
    setup_py_path = REPO / 'setup.py'
    assert setup_py_path.is_file(), f'{setup_py_path} is missing.'

    content = setup_py_path.read_text()
    assert 'RustExtension' in content, 'setup.py does not use RustExtension to build the Rust code.'
    assert 'setuptools_rust' in content, 'setup.py does not import from setuptools_rust.'


def test_rust_code_fixed():
    """Test that the Rust code uses owned Strings instead of borrowed references."""
    lib_rs_path = REPO / 'src/lib.rs'
    assert lib_rs_path.is_file(), f'{lib_rs_path} is missing.'

    content = lib_rs_path.read_text()
    assert 'String' in content, 'lib.rs should use owned `String` types for `level` and `message` instead of borrowed `&str`.'
    assert "<'a>" not in content, 'lib.rs should not have lifetime parameters on `LogEntry` anymore, as PyO3 does not support them.'

    # Ignore comments before checking that the actual LogEntry fields own data.
    code = re.sub(r'/\*.*?\*/', '', content, flags=re.S)
    code = re.sub(r'//.*', '', code)
    match = re.search(r'(?:pub\s+)?struct\s+LogEntry\s*\{(?P<body>.*?)\}', code, re.S)
    assert match, 'lib.rs must define the LogEntry struct.'
    body = match.group('body')
    assert re.search(r'pub\s+level\s*:\s*String\b', body), 'LogEntry.level must be an owned String.'
    assert re.search(r'pub\s+message\s*:\s*String\b', body), 'LogEntry.message must be an owned String.'


def test_clean_rust_build_and_native_extension():
    """Perform a clean setuptools-rust build and ensure Parser comes from its Rust shared library."""
    shutil.rmtree(REPO / 'target', ignore_errors=True)
    for suffix in importlib.machinery.EXTENSION_SUFFIXES:
        for artifact in REPO.rglob('*' + suffix):
            artifact.unlink()

    build = subprocess.run(
        [sys.executable, 'setup.py', 'build_rust', '--inplace'],
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    assert build.returncode == 0, f'setup.py build_rust --inplace failed:\n{build.stdout}'

    install = subprocess.run(
        [sys.executable, '-m', 'pip', 'install', '-e', '.', '--no-build-isolation'],
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=300,
    )
    assert install.returncode == 0, f'pip install -e . failed:\n{install.stdout}'

    cargo_libraries = [p for p in (REPO / 'target').rglob('*.so') if p.is_file()]
    assert cargo_libraries, 'The clean build did not produce a Rust cdylib under target/.'
    cargo_hashes = {hashlib.sha256(p.read_bytes()).hexdigest() for p in cargo_libraries}

    probe = r'''
import hashlib, importlib, importlib.machinery, json
import log_parser_accel
assert hasattr(log_parser_accel, "Parser")
owner = importlib.import_module(log_parser_accel.Parser.__module__)
spec = owner.__spec__
assert isinstance(spec.loader, importlib.machinery.ExtensionFileLoader), (
    f"Parser is defined by {spec.loader!r}, not a compiled extension"
)
path = spec.origin
print(json.dumps({"path": path, "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest()}))
'''
    proc = subprocess.run(
        [sys.executable, '-c', probe],
        cwd='/tmp',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f'Native extension provenance check failed:\n{proc.stderr}'
    info = json.loads(proc.stdout.strip().splitlines()[-1])
    assert any(info['path'].endswith(s) for s in importlib.machinery.EXTENSION_SUFFIXES)
    assert info['sha256'] in cargo_hashes, 'The imported Parser is not from the freshly built Rust cdylib.'


def test_package_installed_and_usable():
    """Test that the installed native package exposes a stateful Parser."""
    try:
        import log_parser_accel
    except ImportError:
        pytest.fail('log_parser_accel is not installed or fails to import. Did you run `pip install -e .`?')

    assert hasattr(log_parser_accel, 'Parser'), 'The `Parser` class is not exposed by the `log_parser_accel` module.'

    parser = log_parser_accel.Parser()
    assert parser.parse_line('BEGIN') is None
    entry = parser.parse_line('ERROR: Test')
    assert entry is not None
    assert entry.level == 'ERROR'
    assert entry.message == 'Test'

    # Exercise non-fixed values and state transitions.
    token = os.urandom(12).hex()
    assert parser.parse_line('END') is None
    assert parser.parse_line(f'OUTSIDE: {token}') is None
    assert parser.parse_line('BEGIN transaction-' + token) is None
    entry = parser.parse_line(f'  LEVEL-{token}  :  message:{token}:tail  ')
    assert entry is not None
    assert entry.level == f'LEVEL-{token}'
    assert entry.message == f'message:{token}:tail'
    assert parser.parse_line('END transaction-' + token) is None
    assert parser.parse_line(f'AFTER: {token}') is None


def test_run_parser_script_exists():
    """Test that the validation script was created."""
    script_path = Path('/home/user/run_parser.py')
    assert script_path.is_file(), f'{script_path} is missing.'


def expected_for_log(text):
    expected = []
    in_transaction = False
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith('BEGIN'):
            in_transaction = True
        elif line.startswith('END'):
            in_transaction = False
        elif in_transaction and ':' in line:
            level, message = line.split(':', 1)
            expected.append({'level': level.strip(), 'message': message.strip()})
    return expected


def test_release_results():
    """Test that the JSON output matches the expected parsed log entries."""
    log_path = Path('/home/user/server.log')
    results_path = Path('/home/user/release_results.json')
    assert results_path.is_file(), f'{results_path} is missing. The script should generate this file.'

    expected = expected_for_log(log_path.read_text())
    try:
        data = json.loads(results_path.read_text())
    except json.JSONDecodeError:
        pytest.fail(f'{results_path} does not contain valid JSON.')
    assert data == expected, f'The contents of {results_path} do not match the expected parsed logs.\nExpected: {expected}\nGot: {data}'


def test_run_parser_is_executed_on_dynamic_log():
    """Execute run_parser.py against unpredictable input rather than trusting a prewritten JSON file."""
    log_path = Path('/home/user/server.log')
    results_path = Path('/home/user/release_results.json')
    script_path = Path('/home/user/run_parser.py')
    old_log = log_path.read_bytes()
    old_results = results_path.read_bytes() if results_path.exists() else None
    token = os.urandom(16).hex()
    dynamic_log = f'''NOISE: {token}\nBEGIN {token}\nALPHA-{token}: first:{token}\nline without colon\n BETA-{token} : second value \nEND {token}\nIGNORED: {token}\nBEGIN\nOMEGA: final-{token}\nEND\n'''

    try:
        log_path.write_text(dynamic_log)
        if results_path.exists():
            results_path.unlink()
        proc = subprocess.run(
            [sys.executable, str(script_path)],
            cwd='/tmp',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert proc.returncode == 0, f'run_parser.py failed:\n{proc.stdout}\n{proc.stderr}'
        assert results_path.is_file(), 'Executing run_parser.py did not create release_results.json.'
        assert json.loads(results_path.read_text()) == expected_for_log(dynamic_log)
    finally:
        log_path.write_bytes(old_log)
        if old_results is None:
            results_path.unlink(missing_ok=True)
        else:
            results_path.write_bytes(old_results)


def test_run_parser_actually_uses_parser_class():
    """Inject a recording Parser and verify the script imports and consumes parse_line results."""
    log_path = Path('/home/user/server.log')
    results_path = Path('/home/user/release_results.json')
    old_log = log_path.read_bytes()
    old_results = results_path.read_bytes() if results_path.exists() else None
    token = os.urandom(10).hex()
    lines = ['BEGIN', f'RAW: {token}', 'skip this', 'END']

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        marker = td / 'calls.jsonl'
        package = td / 'log_parser_accel'
        package.mkdir()
        (package / '__init__.py').write_text(f'''
import json
MARKER = {str(marker)!r}
class Entry:
    def __init__(self, level, message):
        self.level = level
        self.message = message
class Parser:
    def parse_line(self, line):
        clean = line.strip()
        with open(MARKER, "a") as f:
            f.write(json.dumps(clean) + "\\n")
        if ":" in clean:
            left, right = clean.split(":", 1)
            return Entry("HOOK-" + left.strip(), "HOOK-" + right.strip()[::-1])
        return None
''')
        try:
            log_path.write_text('\n'.join(lines) + '\n')
            results_path.unlink(missing_ok=True)
            env = os.environ.copy()
            env['PYTHONPATH'] = str(td)
            proc = subprocess.run(
                [sys.executable, '/home/user/run_parser.py'],
                cwd='/tmp',
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert proc.returncode == 0, f'run_parser.py failed with an injected Parser:\n{proc.stderr}'
            assert marker.is_file(), 'run_parser.py did not instantiate/use log_parser_accel.Parser.'
            calls = [json.loads(x) for x in marker.read_text().splitlines()]
            assert calls == lines, 'run_parser.py must pass each server.log line to Parser.parse_line.'
            assert json.loads(results_path.read_text()) == [
                {'level': 'HOOK-RAW', 'message': 'HOOK-' + token[::-1]}
            ], 'run_parser.py did not collect the LogEntry objects returned by Parser.parse_line.'
        finally:
            log_path.write_bytes(old_log)
            if old_results is None:
                results_path.unlink(missing_ok=True)
            else:
                results_path.write_bytes(old_results)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
