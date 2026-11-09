#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile

import pytest

ARCHIVE = '/home/user/archive.db'
ASSETS = '/home/user/assets'
SCRIPT = '/home/user/compress_assets.py'
VENDORED_CORE = '/app/fast-dedup-1.2.0/fast_dedup/core.py'
CHUNK_SIZE = 104856


def expected_archive(input_dir):
    metadata = {}
    blocks = {}
    for filename in os.listdir(input_dir):
        path = os.path.join(input_dir, filename)
        if not os.path.isfile(path):
            continue
        hashes = []
        with open(path, 'rb') as f:
            f.read(16)
            while True:
                chunk = f.read(CHUNK_SIZE)
                if not chunk:
                    break
                digest = hashlib.sha256(chunk).hexdigest()
                blocks.setdefault(digest, chunk.hex())
                hashes.append(digest)
        metadata[filename] = hashes
    return {'metadata': metadata, 'blocks': blocks}


def assert_valid_archive(path, expected):
    assert os.path.exists(path), f'Output file {path} does not exist.'
    assert os.path.isfile(path), f'Output path {path} is not a file.'
    assert not os.path.islink(path), f'Output path {path} must be a regular file, not a symlink.'
    assert stat.S_ISREG(os.lstat(path).st_mode), f'Output path {path} is not a regular file.'
    assert os.path.getsize(path) > 0, f'Archive file {path} is empty.'
    try:
        with open(path, 'rb') as f:
            data = json.loads(f.read().decode('utf-8'))
    except Exception as exc:
        pytest.fail(f'{path} is not a valid fast-dedup archive: {exc}')
    assert data == expected, 'Archive metadata or deduplicated blocks do not match the input files.'


def make_hidden_inputs(directory):
    common = os.urandom(CHUNK_SIZE)
    other = os.urandom(CHUNK_SIZE)
    tail = os.urandom(7919)
    files = {
        'one.bin': os.urandom(16) + common + other + tail,
        'two.bin': os.urandom(16) + common + common,
        'three.bin': os.urandom(16) + other + tail,
    }
    for name, contents in files.items():
        with open(os.path.join(directory, name), 'wb') as f:
            f.write(contents)


def test_vendored_and_installed_package_work_on_hidden_inputs():
    assert os.path.isfile(VENDORED_CORE), 'Vendored fast-dedup core.py is missing.'

    with tempfile.TemporaryDirectory(prefix='dedup-hidden-') as input_dir, tempfile.TemporaryDirectory(prefix='dedup-out-') as output_dir:
        make_hidden_inputs(input_dir)
        expected = expected_archive(input_dir)

        spec = importlib.util.spec_from_file_location('_checked_vendored_fast_dedup_core', VENDORED_CORE)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        vendored_output = os.path.join(output_dir, 'vendored.db')
        module.deduplicate_directory(input_dir, vendored_output)
        assert_valid_archive(vendored_output, expected)

        installed_output = os.path.join(output_dir, 'installed.db')
        code = (
            "import importlib.metadata, sys\n"
            "assert importlib.metadata.version('fast-dedup') == '1.2.0'\n"
            "import fast_dedup\n"
            "fast_dedup.deduplicate_directory(sys.argv[1], sys.argv[2])\n"
        )
        result = subprocess.run(
            [sys.executable, '-I', '-c', code, input_dir, installed_output],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f'Installed fast-dedup failed: {result.stdout}'
        assert_valid_archive(installed_output, expected)


def test_script_executes_library_and_produces_real_compressed_archive():
    assert os.path.isfile(SCRIPT), f'Required script {SCRIPT} does not exist.'
    assert not os.path.islink(SCRIPT), f'{SCRIPT} must be a regular file.'

    with open(SCRIPT, 'r', encoding='utf-8') as f:
        tree = ast.parse(f.read(), filename=SCRIPT)

    module_aliases = set()
    function_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'fast_dedup':
                    module_aliases.add(alias.asname or 'fast_dedup')
        elif isinstance(node, ast.ImportFrom) and node.module == 'fast_dedup':
            for alias in node.names:
                if alias.name == 'deduplicate_directory':
                    function_aliases.add(alias.asname or alias.name)

    assert module_aliases or function_aliases, f'{SCRIPT} does not import fast_dedup.'
    calls_library = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in function_aliases:
            calls_library = True
        if (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == 'deduplicate_directory'
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in module_aliases
        ):
            calls_library = True
    assert calls_library, f'{SCRIPT} does not call fast_dedup.deduplicate_directory.'

    assert os.path.isdir(ASSETS), f'Assets directory {ASSETS} is missing.'
    expected_names = {f'asset_{i:03d}.bin' for i in range(100)}
    actual_names = {
        name for name in os.listdir(ASSETS)
        if os.path.isfile(os.path.join(ASSETS, name))
    }
    assert actual_names == expected_names, 'The supplied asset set was removed or replaced.'
    assert all(os.path.getsize(os.path.join(ASSETS, name)) == 1048576 for name in expected_names), 'An input asset has been modified or truncated.'
    expected = expected_archive(ASSETS)

    if os.path.lexists(ARCHIVE):
        assert not os.path.isdir(ARCHIVE), f'{ARCHIVE} is a directory.'
        os.unlink(ARCHIVE)

    result = subprocess.run(
        [sys.executable, '-I', SCRIPT],
        cwd='/tmp',
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f'compress_assets.py failed: {result.stdout}'
    assert_valid_archive(ARCHIVE, expected)

    # Preserve the original archive existence and compression assertions.
    archive_path = '/home/user/archive.db'
    assets_dir = '/home/user/assets'

    assert os.path.exists(archive_path), f'Output file {archive_path} does not exist.'
    assert os.path.isfile(archive_path), f'Output path {archive_path} is not a file.'

    archive_size = os.path.getsize(archive_path)

    if os.path.exists(assets_dir) and os.path.isdir(assets_dir):
        original_size = sum(
            os.path.getsize(os.path.join(assets_dir, f))
            for f in os.listdir(assets_dir)
            if os.path.isfile(os.path.join(assets_dir, f))
        )
    else:
        original_size = 104857600

    assert original_size > 0, 'Original size is 0, cannot compute compression ratio.'
    assert archive_size > 0, f'Archive file {archive_path} is empty.'

    ratio = original_size / archive_size
    threshold = 2.85
    assert ratio >= threshold, (
        f'Compression ratio too low. Original size: {original_size} bytes, '
        f'Archive size: {archive_size} bytes. Ratio achieved: {ratio:.2f}x. '
        f'Required ratio: >= {threshold}x.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
