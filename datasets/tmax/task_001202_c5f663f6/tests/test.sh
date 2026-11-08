#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import site
import string
import subprocess
import sys
import tempfile

import pytest


def python_env():
    env = os.environ.copy()
    user_sites = glob.glob('/home/user/.local/lib/python*/site-packages')
    if user_sites:
        old = env.get('PYTHONPATH', '')
        env['PYTHONPATH'] = os.pathsep.join(user_sites + ([old] if old else []))
    return env


def test_toml_fixed_and_installed():
    """Verify that the vendored toml package is fixed and installed correctly."""
    decoder = '/app/toml-0.10.2/toml/decoder.py'
    assert os.path.isfile(decoder), 'Vendored toml decoder is missing.'
    source = open(decoder, encoding='utf-8').read()
    assert 'import datatime' not in source, 'The deliberate toml typo is still present.'
    assert 'import datetime' in source, 'The toml datetime import was not repaired.'

    for path in glob.glob('/home/user/.local/lib/python*/site-packages'):
        site.addsitedir(path)

    try:
        import toml
    except ImportError as e:
        pytest.fail(f"Failed to import 'toml'. Did you install it? Error: {e}")

    try:
        parsed = toml.loads('a = 1')
        assert parsed == {'a': 1}, 'toml package did not parse correctly.'
    except Exception as e:
        pytest.fail(f'toml package is still broken: {e}')


def generate_random_string(length=8):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def create_fuzz_directory(base_dir):
    expected = []
    nested = os.path.join(base_dir, 'nested', generate_random_string(5))
    os.makedirs(nested)

    encodings = ['utf-8', 'utf-16le', 'cp1252']
    statuses = ['released', 'beta', 'alpha', 'deprecated']

    # Guarantee coverage of every supported encoding, including UTF-16LE text
    # whose bytes are also technically decodable as UTF-8.
    for i in range(9):
        encoding = encodings[i % len(encodings)]
        status = 'released' if i < 3 else random.choice(statuses)
        if encoding == 'cp1252':
            name = f'Café-{generate_random_string(8)}'
        else:
            name = generate_random_string(10)
        version = f'{random.randint(0, 5)}.{random.randint(0, 9)}.{random.randint(0, 9)}'
        architecture = random.choice(['amd64', 'arm64', 'x86', 'armhf'])
        content = (
            '[metadata]\n'
            f'artifact_name = "{name}"\n'
            f'version = "{version}"\n'
            f'architecture = "{architecture}"\n'
            f'status = "{status}"\n'
        )
        directory = nested if i % 2 else base_dir
        filepath = os.path.join(directory, f'file_{i}_{generate_random_string(4)}.manifest')
        with open(filepath, 'w', encoding=encoding) as f:
            f.write(content)
        if status == 'released':
            expected.append({'name': name, 'version': version, 'arch': architecture})

    for i in range(random.randint(2, 6)):
        ext = random.choice(['.bin', '.txt'])
        with open(os.path.join(base_dir, f'noise_{i}_{generate_random_string(4)}{ext}'), 'wb') as f:
            f.write(os.urandom(32))

    expected.sort(key=lambda item: item['name'])
    return json.dumps(expected, separators=(',', ':'))


def test_fuzz_equivalence():
    """Exercise the submitted script and derive expected answers from generated inputs."""
    agent_script = '/home/user/curate.py'
    assert os.path.isfile(agent_script), f'Agent script not found at {agent_script}'

    random.seed(42)
    for i in range(20):
        with tempfile.TemporaryDirectory() as temp_dir:
            expected = create_fuzz_directory(temp_dir)
            try:
                result = subprocess.run(
                    [sys.executable, agent_script, temp_dir],
                    capture_output=True,
                    text=True,
                    check=True,
                    env=python_env(),
                )
            except subprocess.CalledProcessError as e:
                pytest.fail(f'Agent script failed on fuzz iteration {i}: {e.stderr}')

            actual = result.stdout.strip()
            if actual != expected:
                pytest.fail(
                    f'Mismatch found on fuzz iteration {i}.\n'
                    f'Expected:\n{expected}\n\nAgent output:\n{actual}\n'
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
