#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import string
import subprocess


def expected_curated_name(path):
    base = os.path.basename(path)
    if '.' in base:
        base = base.split('.', 1)[0]
    base = base.lower()
    base = base.replace(' ', '-').replace('_', '-')
    return base + '-curated.bin'


def test_curated_binaries_directory():
    curated_dir = '/home/user/curated_binaries'
    assert os.path.isdir(curated_dir), f'Directory {curated_dir} does not exist.'
    files = os.listdir(curated_dir)
    assert len(files) > 0, f'Directory {curated_dir} is empty. Expected extracted and renamed files.'
    for filename in files:
        assert filename.endswith('-curated.bin'), (
            f"File {filename} in {curated_dir} does not have the expected suffix '-curated.bin'."
        )

    expected_files = {
        'to-my-file-curated.bin': b'dummy binary data 1',
        'no-extension-file-curated.bin': b'dummy binary data 2',
        '--leading-spaces-curated.bin': b'dummy binary data 3',
    }
    assert set(files) == set(expected_files), (
        f'Curated directory has incorrect contents. Expected {sorted(expected_files)}, got {sorted(files)}.'
    )

    for filename, expected_data in expected_files.items():
        path = os.path.join(curated_dir, filename)
        mode = os.lstat(path).st_mode
        assert stat.S_ISREG(mode), f'{path} must be a regular file, not a link or directory.'
        with open(path, 'rb') as handle:
            actual_data = handle.read()
        assert actual_data == expected_data, f'Binary contents are incorrect for {filename}.'


def test_artifact_namer_executable():
    namer_path = '/home/user/artifact_namer'
    assert os.path.isfile(namer_path), f'Executable {namer_path} does not exist.'
    assert os.access(namer_path, os.X_OK), f'File {namer_path} is not executable.'


def test_fuzz_equivalence():
    agent_namer = '/home/user/artifact_namer'
    assert os.path.isfile(agent_namer), f'Agent program {agent_namer} is missing.'

    fixed_inputs = [
        'To_My File.v2.tar.gz',
        'NO_EXTENSION_FILE',
        'dir1/dir2/  leading spaces.txt',
        '/a/b/.hidden',
        'a.b.c',
        'trailing/path/',
        'MiXeD__ Name',
    ]

    random.seed(42)
    chars = string.ascii_letters + string.digits + ' _./'
    fuzz_inputs = [
        ''.join(random.choices(chars, k=random.randint(1, 100)))
        for _ in range(1000)
    ]

    for test_input in fixed_inputs + fuzz_inputs:
        expected = expected_curated_name(test_input)
        agent_proc = subprocess.run(
            [agent_namer, test_input],
            capture_output=True,
            text=True,
            timeout=5,
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, (
            f'Program exited with status {agent_proc.returncode} on input {test_input!r}: '
            f'{agent_proc.stderr!r}'
        )
        assert expected == agent_out, (
            f'Mismatch on input: {test_input!r}\n'
            f'Expected: {expected!r}\n'
            f'Got:      {agent_out!r}'
        )


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
