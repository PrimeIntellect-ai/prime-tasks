#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import importlib.util
import inspect
import json
import os
from pathlib import Path
import random
import subprocess
import sys

WORK = Path('/home/user/voice_sec')
SANITIZER = WORK / 'sanitizer.py'
USER_TEST = WORK / 'test_sanitizer.py'
VENV = WORK / 'venv'
CLEAN = Path('/app/corpora/clean')
EVIL = Path('/app/corpora/evil')

EXPECTED_CLEAN = {
    'note1.txt': 'hello this is a voice note\n',
    'note2.txt': 'remind me to buy groceries tomorrow\n',
    'note3.txt': 'what is the weather like today\n',
}
EXPECTED_EVIL = {
    'attack1.txt': '<script>alert(1)</script>\n',
    'attack2.txt': 'DROP TABLE users;\n',
    'attack3.txt': 'SELECT * FROM passwords WHERE 1=1\n',
    'attack4.txt': '../../../etc/passwd\n',
}


def load_sanitizer():
    assert SANITIZER.is_file(), f'Expected sanitizer module at {SANITIZER}'
    spec = importlib.util.spec_from_file_location('submitted_sanitizer', SANITIZER)
    assert spec and spec.loader, 'Could not load sanitizer.py'
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, 'is_safe_input'), "sanitizer.py is missing the 'is_safe_input' function"
    fn = module.is_safe_input
    assert inspect.isfunction(fn), 'is_safe_input must be a Python function'
    signature = inspect.signature(fn)
    assert list(signature.parameters) == ['transcribed_text'], \
        'is_safe_input must have exactly the parameter transcribed_text'
    return fn


def test_required_environment_and_pytest_installation():
    assert WORK.is_dir(), f'Working directory not found at {WORK}'
    assert (VENV / 'pyvenv.cfg').is_file(), 'The required virtual environment was not created at /home/user/voice_sec/venv'
    python = VENV / 'bin/python'
    pytest_exe = VENV / 'bin/pytest'
    assert python.is_file() and os.access(python, os.X_OK), 'Virtual-environment Python is missing'
    assert pytest_exe.is_file() and os.access(pytest_exe, os.X_OK), 'pytest is not installed in the virtual environment'
    check = subprocess.run(
        [str(python), '-c',
         "import pathlib,sys,pytest; print(pathlib.Path(sys.prefix).resolve()); print(pytest.__version__)"],
        text=True, capture_output=True, timeout=20
    )
    assert check.returncode == 0, f'pytest cannot be imported in the virtual environment: {check.stderr}'
    assert check.stdout.splitlines()[0] == str(VENV.resolve()), 'Python did not run from the required virtual environment'


def test_original_corpora_and_sanitizer_behavior():
    for name, expected in EXPECTED_CLEAN.items():
        path = CLEAN / name
        assert path.is_file(), f'Missing supplied clean corpus file: {path}'
        assert path.read_text() == expected, f'Supplied corpus file was modified: {path}'
    for name, expected in EXPECTED_EVIL.items():
        path = EVIL / name
        assert path.is_file(), f'Missing supplied evil corpus file: {path}'
        assert path.read_text() == expected, f'Supplied corpus file was modified: {path}'

    fn = load_sanitizer()
    failed_clean = []
    for path in CLEAN.iterdir():
        if path.name.endswith('.txt') and fn(path.read_text()) is not True:
            failed_clean.append(path.name)
    failed_evil = []
    for path in EVIL.iterdir():
        if path.name.endswith('.txt') and fn(path.read_text()) is not False:
            failed_evil.append(path.name)

    total_clean = len([p for p in CLEAN.iterdir() if p.name.endswith('.txt')])
    total_evil = len([p for p in EVIL.iterdir() if p.name.endswith('.txt')])
    errors = []
    if failed_clean:
        errors.append(f'{len(failed_clean)} of {total_clean} clean modified/rejected. Offending files: {", ".join(failed_clean)}')
    if failed_evil:
        errors.append(f'{len(failed_evil)} of {total_evil} evil bypassed/accepted. Offending files: {", ".join(failed_evil)}')
    assert not errors, ' | '.join(errors)


def test_sanitizer_on_derived_adversarial_inputs():
    fn = load_sanitizer()
    seed_material = Path('/app/incident_042.wav').read_bytes()
    rng = random.Random(int.from_bytes(hashlib.sha256(seed_material).digest()[:8], 'big'))

    def mixed_case(value):
        return ''.join(c.upper() if rng.randrange(2) else c.lower() for c in value)

    suffix = ''.join(rng.choice('abcdefghijkmnpqrstuvwxyz') for _ in range(9))
    malicious = [
        f"<{mixed_case('script')} >alert('{suffix}')</{mixed_case('script')}>",
        f'<img src=x onerror=alert({rng.randrange(100, 999)})>',
        f"{mixed_case('drop')}\tTABLE audit_{suffix}; --",
        f"{mixed_case('select')} id,name FROM accounts_{suffix} WHERE id='1' OR '1'='1';",
        f"{mixed_case('delete')} FROM sessions_{suffix} WHERE id=1; --",
        f"' UNION {mixed_case('select')} password FROM users_{suffix} --",
        ('../' * rng.randrange(3, 7)) + f'etc/{suffix}/passwd',
    ]
    benign = [
        f'please select the blue folder named {suffix}',
        f'please drop the package near the front door {suffix}',
        f'the weather report for {suffix} says it will be sunny',
        f'remind me to buy bread milk and apples {suffix}',
        f'delete my reminder about the dentist appointment {suffix}',
    ]

    for text in malicious:
        result = fn(text)
        assert type(result) is bool, f'is_safe_input must return bool, got {type(result).__name__}'
        assert result is False, f'Malicious input was accepted: {text!r}'
    for text in benign:
        result = fn(text)
        assert type(result) is bool, f'is_safe_input must return bool, got {type(result).__name__}'
        assert result is True, f'Benign input was rejected: {text!r}'


def test_submitted_pytest_suite_is_dynamic_and_runs():
    assert USER_TEST.is_file(), f'Expected pytest suite at {USER_TEST}'
    source = USER_TEST.read_text()
    tree = ast.parse(source, filename=str(USER_TEST))

    fixture_names = set()
    test_args = set()
    has_dynamic_read = False
    has_sanitizer_assert = False
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for decorator in node.decorator_list:
                name = decorator.func if isinstance(decorator, ast.Call) else decorator
                if ((isinstance(name, ast.Name) and name.id == 'fixture') or
                    (isinstance(name, ast.Attribute) and name.attr == 'fixture')):
                    fixture_names.add(node.name)
            if node.name.startswith('test_'):
                test_args.update(arg.arg for arg in node.args.args)
        if isinstance(node, ast.Call):
            called = node.func
            if ((isinstance(called, ast.Attribute) and called.attr in {'listdir', 'glob', 'rglob', 'iterdir'}) or
                (isinstance(called, ast.Name) and called.id in {'glob', 'listdir'})):
                has_dynamic_read = True
        if isinstance(node, ast.Assert):
            if any((isinstance(child, ast.Name) and child.id == 'is_safe_input') or
                   (isinstance(child, ast.Attribute) and child.attr == 'is_safe_input')
                   for child in ast.walk(node.test)):
                has_sanitizer_assert = True

    assert fixture_names, 'The submitted pytest suite must define pytest fixtures'
    assert fixture_names & test_args, 'At least one submitted test must consume a pytest fixture'
    assert has_dynamic_read, 'The submitted suite must dynamically enumerate corpus files'
    assert '/app/corpora/clean' in source and '/app/corpora/evil' in source, \
        'The submitted suite must load both supplied corpus directories'
    assert has_sanitizer_assert, 'The submitted suite must assert results from is_safe_input'

    token = hashlib.sha256(Path('/app/incident_042.wav').read_bytes() + source.encode()).hexdigest()[:12]
    added_clean = CLEAN / f'verifier_clean_{token}.txt'
    added_evil = EVIL / f'verifier_evil_{token}.txt'
    clean_text = f'please record a calm voice memo number {token}\n'
    evil_text = f"<ScRiPt>alert('{token}')</sCrIpT>\n"
    added_clean.write_text(clean_text)
    added_evil.write_text(evil_text)

    trace_file = Path('/tmp/user_suite_calls.json')
    runner = Path('/tmp/run_submitted_suite.py')
    runner.write_text(r'''import json, os, sys
from pathlib import Path
calls = []
san = os.path.realpath('/home/user/voice_sec/sanitizer.py')
def trace(frame, event, arg):
    if event == 'call' and os.path.realpath(frame.f_code.co_filename) == san and frame.f_code.co_name == 'is_safe_input':
        calls.append(frame.f_locals.get('transcribed_text'))
    return trace
sys.path.insert(0, '/home/user/voice_sec')
sys.settrace(trace)
import pytest
code = pytest.main(['/home/user/voice_sec/test_sanitizer.py', '-q', '--tb=short'])
sys.settrace(None)
Path('/tmp/user_suite_calls.json').write_text(json.dumps(calls))
raise SystemExit(int(code))
''')
    try:
        result = subprocess.run(
            [str(VENV / 'bin/python'), str(runner)], cwd=str(WORK),
            text=True, capture_output=True, timeout=60
        )
        assert result.returncode == 0, \
            f'Submitted pytest suite failed under the required virtual environment:\n{result.stdout}\n{result.stderr}'
        assert trace_file.is_file(), 'Could not observe calls made by the submitted pytest suite'
        calls = json.loads(trace_file.read_text())
        required = [p.read_text() for p in CLEAN.glob('*.txt')] + [p.read_text() for p in EVIL.glob('*.txt')]
        missing = [text for text in required if text not in calls]
        assert not missing, 'The submitted pytest suite did not exercise every dynamically present corpus file'
    finally:
        added_clean.unlink(missing_ok=True)
        added_evil.unlink(missing_ok=True)


def test_incident_transcript_and_verdict_log():
    audio = Path('/app/incident_042.wav')
    stub = Path('/app/bin/whisper-stub')
    transcript = WORK / 'incident_transcript.txt'
    log_path = WORK / 'incident_verdict.log'
    assert audio.is_file(), 'Incident audio file is missing'
    assert stub.is_file() and os.access(stub, os.X_OK), 'whisper-stub is missing or not executable'
    assert transcript.is_file(), f'Expected transcript file not found at {transcript}'

    expected_transcript = subprocess.check_output([str(stub), str(audio)])
    assert expected_transcript == b'DELETE FROM users WHERE id=1; --\n', 'The supplied whisper-stub was modified'
    assert transcript.read_bytes() == expected_transcript, \
        'incident_transcript.txt is not the exact output of the required whisper-stub command'

    assert log_path.is_file(), f'Expected log file not found at {log_path}'
    content = log_path.read_text().strip()
    assert content == 'VERDICT: EVIL', f"Expected 'VERDICT: EVIL' in {log_path}, got '{content}'"
    assert log_path.read_bytes() in {b'VERDICT: EVIL', b'VERDICT: EVIL\n'}, \
        'incident_verdict.log must contain exactly one verdict line'

    fn = load_sanitizer()
    result = fn(transcript.read_text())
    assert type(result) is bool, 'is_safe_input must return a bool for the incident transcript'
    expected_verdict = 'VERDICT: CLEAN' if result else 'VERDICT: EVIL'
    assert content == expected_verdict, 'Incident verdict does not match is_safe_input(transcript)'
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
