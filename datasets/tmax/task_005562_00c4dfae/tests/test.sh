#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import hashlib
import os
import pathlib
import subprocess
import sys
import tempfile
import zipfile

PROJECT = pathlib.Path('/home/user/project')
ARTIFACTS = pathlib.Path('/home/user/ci_artifacts')


def test_pytest_passes():
    """Keep the original requirement that the submitted test suite passes."""
    result = subprocess.run(
        ['pytest', str(PROJECT / 'test_main.py')],
        cwd=str(PROJECT),
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f'pytest failed with exit code {result.returncode}.\n'
        f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )


def test_test_main_contains_the_required_ordering_fix_and_assertion():
    """Reject an emptied or replaced test file while allowing the intended reorder."""
    test_path = PROJECT / 'test_main.py'
    tree = ast.parse(test_path.read_text(), filename=str(test_path))

    env_assignment_lines = []
    main_import_lines = []
    has_test_function = False
    has_429_assertion = False

    for node in ast.walk(tree):
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            if isinstance(node, ast.ImportFrom) and node.module == 'main':
                main_import_lines.append(node.lineno)
            elif isinstance(node, ast.Import):
                for alias in node.names:
                    if alias.name == 'main':
                        main_import_lines.append(node.lineno)

        if isinstance(node, ast.Assign):
            for target in node.targets:
                if (
                    isinstance(target, ast.Subscript)
                    and isinstance(target.value, ast.Attribute)
                    and isinstance(target.value.value, ast.Name)
                    and target.value.value.id == 'os'
                    and target.value.attr == 'environ'
                ):
                    key = target.slice
                    if isinstance(key, ast.Constant) and key.value == 'TEST_MODE':
                        if isinstance(node.value, ast.Constant) and node.value.value == '1':
                            env_assignment_lines.append(node.lineno)

        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == 'test_read_root':
            has_test_function = True

        if isinstance(node, ast.Assert):
            for child in ast.walk(node.test):
                if isinstance(child, ast.Constant) and child.value == 429:
                    has_429_assertion = True

    assert main_import_lines, 'test_main.py must import the application from main'
    assert env_assignment_lines, 'test_main.py must set os.environ["TEST_MODE"] to "1"'
    assert min(env_assignment_lines) < min(main_import_lines), (
        'TEST_MODE must be set before importing main'
    )
    assert has_test_function, 'test_main.py must retain test_read_root'
    assert has_429_assertion, 'test_main.py must retain an assertion for HTTP status 429'


def test_rust_source_compiles_independently():
    """Compile the current Rust source in a fresh target directory."""
    assert (PROJECT / 'src/lib.rs').is_file(), 'src/lib.rs is missing'
    with tempfile.TemporaryDirectory(prefix='cargo-target-') as target:
        env = os.environ.copy()
        env['CARGO_TARGET_DIR'] = target
        result = subprocess.run(
            [
                'cargo', 'check', '--release',
                '--manifest-path', str(PROJECT / 'Cargo.toml'),
            ],
            cwd=str(PROJECT),
            env=env,
            capture_output=True,
            text=True,
            timeout=600,
        )
    assert result.returncode == 0, (
        f'Rust source did not compile.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )


def _wheel_and_extension():
    wheels = glob.glob(str(ARTIFACTS / '*.whl'))
    assert len(wheels) == 1, (
        f'Expected exactly 1 .whl file in /home/user/ci_artifacts, '
        f'found {len(wheels)}: {wheels}'
    )
    wheel = pathlib.Path(wheels[0])
    assert zipfile.is_zipfile(wheel), f'{wheel} is not a valid wheel/ZIP archive'

    extracted = tempfile.TemporaryDirectory(prefix='submitted-wheel-')
    with zipfile.ZipFile(wheel) as archive:
        bad = archive.testzip()
        assert bad is None, f'Wheel contains a corrupt member: {bad}'
        archive.extractall(extracted.name)

    extension_files = [
        p for p in pathlib.Path(extracted.name).rglob('*.so')
        if p.name.startswith('rate_limiter')
    ]
    assert len(extension_files) == 1, (
        f'Expected one compiled rate_limiter shared library in the wheel, '
        f'found {extension_files}'
    )
    return wheel, extracted, extension_files[0]


def test_wheel_generated_installed_and_functional():
    """Validate and execute the actual extension contained in the submitted wheel."""
    wheel, extracted, extension = _wheel_and_extension()
    try:
        code = r'''
import sys
sys.path.insert(0, sys.argv[1])
import rate_limiter
assert rate_limiter.is_rate_limited("127.0.0.1") is True
assert rate_limiter.is_rate_limited("192.0.2.10") is False
assert rate_limiter.is_rate_limited("") is False
assert rate_limiter.__file__.endswith(tuple(__import__('importlib').machinery.EXTENSION_SUFFIXES))
'''
        result = subprocess.run(
            [sys.executable, '-I', '-c', code, extracted.name],
            cwd='/tmp',
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f'The extension in the wheel could not be imported or behaved incorrectly.\n'
            f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
        )

        expected_hash = hashlib.sha256(extension.read_bytes()).hexdigest()
        installed_candidates = []
        patterns = [
            '/usr/local/lib/python*/site-packages/rate_limiter*.so',
            '/usr/lib/python*/site-packages/rate_limiter*.so',
            '/home/user/.local/lib/python*/site-packages/rate_limiter*.so',
        ]
        for pattern in patterns:
            installed_candidates.extend(glob.glob(pattern))
        matching = [
            path for path in installed_candidates
            if hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest() == expected_hash
        ]
        assert matching, (
            'No installed rate_limiter extension matches the shared library in the wheel; '
            'the built wheel must be installed in the current environment'
        )
    finally:
        extracted.cleanup()


def test_symbols_extracted_from_submitted_binary():
    """Require symbols.txt to be the actual nm -D output for the wheel's extension."""
    symbols_file = ARTIFACTS / 'symbols.txt'
    assert symbols_file.is_file(), (
        f'{symbols_file} does not exist. Ensure you ran nm -D and redirected the output.'
    )

    wheel, extracted, extension = _wheel_and_extension()
    try:
        result = subprocess.run(
            ['nm', '-D', str(extension)],
            capture_output=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f'nm -D failed for the wheel extension: {result.stderr.decode(errors="replace")}'
        )
        submitted = symbols_file.read_bytes()
        assert submitted == result.stdout, (
            'symbols.txt is not the exact output of nm -D on the compiled extension '
            'contained in the submitted wheel'
        )
        assert b'PyInit_rate_limiter' in submitted, (
            "The symbol 'PyInit_rate_limiter' was not found in symbols.txt."
        )
    finally:
        extracted.cleanup()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
