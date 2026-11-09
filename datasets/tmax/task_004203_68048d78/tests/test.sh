#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import string
import random
import subprocess
import tempfile
from pathlib import Path

import pytest
from packaging.version import Version

PROCESSOR_DIR = Path('/home/user/processor')
AGENT_PROCESSOR = PROCESSOR_DIR / 'processor'
PROCESSOR_SOURCE = PROCESSOR_DIR / 'processor.c'
MAKEFILE = PROCESSOR_DIR / 'Makefile'
API_DIR = Path('/home/user/api_tests')

EXPECTED_API_FILES = {
    'module_a.py': "import sys\nif 'module_b' in sys.modules:\n    raise ImportError(\"module_b cannot be imported before module_a\")\ndef foo(): return 1\n",
    'module_b.py': 'pass\n',
    'test_api.py': 'import module_a\nimport module_b\n\ndef test_something():\n    assert module_a.foo() == 1\n',
}


def expected_transform(data):
    out = bytearray()
    for c in data:
        if 97 <= c <= 122:
            out.append((c - 97 + 13) % 26 + 97)
        elif 65 <= c <= 90:
            out.append((c - 65 + 13) % 26 + 65)
        elif 48 <= c <= 57:
            out.append((c - 48 + 5) % 10 + 48)
        else:
            out.append(c)
    return bytes(out)


def assert_processor_behavior(path):
    cases = [
        b'',
        b'0123456789',
        b'abcdefghijklmnopqrstuvwxyz',
        b'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        b'Hello, API 1.4.2!\n',
        bytes(range(256)),
    ]
    rng = random.Random(7319)
    cases.extend(bytes(rng.randrange(256) for _ in range(rng.randrange(1, 2049))) for _ in range(30))
    for data in cases:
        result = subprocess.run([str(path)], input=data, capture_output=True, timeout=5)
        assert result.returncode == 0, f'{path} exited with {result.returncode}: {result.stderr!r}'
        assert result.stdout == expected_transform(data), f'Incorrect processor output for {data!r}'


def assert_api_files_intact():
    assert API_DIR.is_dir(), f'Test directory {API_DIR} does not exist'
    actual_python = {p.name for p in API_DIR.glob('*.py')}
    assert actual_python == set(EXPECTED_API_FILES), (
        f'Unexpected API test files: expected {set(EXPECTED_API_FILES)}, got {actual_python}'
    )
    for name, expected in EXPECTED_API_FILES.items():
        path = API_DIR / name
        assert path.is_file() and not path.is_symlink(), f'{path} must be a regular file'
        assert path.read_text() == expected, f'{path} is not the correctly patched supplied file'


def selected_version_from_supplied_inputs():
    ocr = subprocess.run(
        ['tesseract', '/app/api_version.png', 'stdout'],
        capture_output=True, text=True, timeout=20, check=True
    ).stdout
    match = re.search(r'VERSION\s*:\s*(\d+\.\d+\.\d+)', ocr, re.I)
    assert match, f'Could not extract a semantic version from image; OCR was {ocr!r}'
    target = Version(match.group(1))
    versions = [Version(line.strip()) for line in Path('/home/user/versions.txt').read_text().splitlines() if line.strip()]
    eligible = [version for version in versions if version <= target]
    assert eligible, 'No supported version is less than or equal to the image version'
    return str(max(eligible))


def test_processor_source_makefile_and_build():
    for path in (PROCESSOR_SOURCE, MAKEFILE):
        assert path.is_file() and not path.is_symlink(), f'{path} must be a regular file'

    source_text = PROCESSOR_SOURCE.read_text(errors='replace')
    make_text = MAKEFILE.read_text(errors='replace')
    combined = source_text + '\n' + make_text
    assert '/app/oracle_processor' not in combined and 'oracle_processor' not in combined, (
        'The source and Makefile may not delegate to or copy the reference executable'
    )
    assert not re.search(r'\b(execl|execv|execve|system|popen)\s*\(', source_text), (
        'processor.c must implement the transformation rather than execute another program'
    )

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        direct_binary = td_path / 'direct_processor'
        compile_result = subprocess.run(
            ['gcc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-o', str(direct_binary), str(PROCESSOR_SOURCE)],
            capture_output=True, text=True
        )
        assert compile_result.returncode == 0, f'processor.c does not compile:\n{compile_result.stdout}\n{compile_result.stderr}'
        assert_processor_behavior(direct_binary)

        build_dir = td_path / 'make_build'
        build_dir.mkdir()
        shutil.copy2(PROCESSOR_SOURCE, build_dir / 'processor.c')
        shutil.copy2(MAKEFILE, build_dir / 'Makefile')

        dry_run = subprocess.run(['make', '-B', '-n', 'processor'], cwd=build_dir, capture_output=True, text=True)
        assert dry_run.returncode == 0, f'Makefile dry run failed:\n{dry_run.stdout}\n{dry_run.stderr}'
        command_text = dry_run.stdout + dry_run.stderr
        assert 'processor.c' in command_text and re.search(r'(^|[ /])(gcc|cc)(\s|$)', command_text), (
            'The processor target must compile processor.c with a C compiler'
        )

        build = subprocess.run(['make', '-B', 'processor'], cwd=build_dir, capture_output=True, text=True)
        assert build.returncode == 0, f'Makefile build failed:\n{build.stdout}\n{build.stderr}'
        built = build_dir / 'processor'
        assert built.is_file() and os.access(built, os.X_OK), 'Makefile did not create an executable processor'
        assert_processor_behavior(built)


def test_processor_fuzz_equivalence():
    oracle_path = '/app/oracle_processor'
    agent_path = '/home/user/processor/processor'

    assert os.path.isfile(agent_path), f'Agent executable not found at {agent_path}'
    assert os.access(agent_path, os.X_OK), f'Agent executable at {agent_path} is not executable'

    random.seed(42)
    printable_chars = string.printable
    for _ in range(100):
        length = random.randint(1, 1000)
        input_str = ''.join(random.choice(printable_chars) for _ in range(length))
        input_data = input_str.encode('utf-8')
        oracle_proc = subprocess.run([oracle_path], input=input_data, capture_output=True)
        agent_proc = subprocess.run([agent_path], input=input_data, capture_output=True)
        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f'Output mismatch on input: {input_data!r}\n'
                f'Oracle output: {oracle_proc.stdout!r}\n'
                f'Agent output: {agent_proc.stdout!r}'
            )


def test_version_selection_script():
    expected = selected_version_from_supplied_inputs()
    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        if API_DIR in path.parents or path.is_symlink() or not path.is_file():
            continue
        text = path.read_text(errors='replace')
        uses_packaging_version = (
            re.search(r'from\s+packaging\.version\s+import\s+.*\bVersion\b', text)
            or re.search(r'\bpackaging\.version\.Version\b', text)
        )
        if 'versions.txt' in text and uses_packaging_version:
            candidates.append(path)

    assert candidates, (
        'No Python version-selection script was found that reads versions.txt and uses packaging.version.Version'
    )

    matched = False
    diagnostics = []
    for path in candidates:
        try:
            result = subprocess.run(
                ['python3', str(path)], cwd='/home/user', capture_output=True, text=True, timeout=30
            )
            output = result.stdout + '\n' + result.stderr
            diagnostics.append(f'{path}: rc={result.returncode}, output={output!r}')
            if result.returncode == 0 and re.search(rf'(?<![0-9.]){re.escape(expected)}(?![0-9.])', output):
                matched = True
                break
        except subprocess.TimeoutExpired:
            diagnostics.append(f'{path}: timed out')

    assert matched, 'No semantic-version selection script produced the derived version ' + expected + '. ' + '; '.join(diagnostics)


def test_api_files_are_correct_patch():
    assert selected_version_from_supplied_inputs() == '1.4.0'
    assert_api_files_intact()


def test_api_tests_pass():
    assert_api_files_intact()
    result = subprocess.run(['pytest', str(API_DIR) + '/'], capture_output=True, text=True)
    assert result.returncode == 0, (
        'API tests did not pass. The correct patch might not have been applied.\n'
        f'Pytest output:\n{result.stdout}\n{result.stderr}'
    )
    assert_api_files_intact()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
