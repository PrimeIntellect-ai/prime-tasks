#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import pwd
import shutil
import signal
import secrets
import subprocess

SCRIPT_PATH = '/home/user/compile_dataset.sh'
OUTPUT_PATH = '/home/user/clean_dataset.txt'
RAW_PATH = '/home/user/raw_data'


def run_script(timeout=10):
    user = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    proc = subprocess.Popen(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env={**os.environ, 'HOME': user.pw_dir, 'LC_ALL': 'C'},
        preexec_fn=demote,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError(f'Script did not finish within {timeout} seconds; traversal may be following a symlink loop.')

    assert proc.returncode == 0, (
        f'Script exited with status {proc.returncode}. '
        f'stdout={stdout!r}, stderr={stderr!r}'
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_contains_required_commands():
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()

    assert "mktemp" in content, "Script does not contain 'mktemp' for secure temporary file creation."

    # Check for atomic move to the final destination
    assert re.search(r"mv\s+.*clean_dataset\.txt", content) is not None, "Script does not contain an atomic 'mv' command to the final destination."


def test_output_file_contents():
    run_script()
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."

    with open(OUTPUT_PATH, 'r') as f:
        actual_lines = f.read().splitlines()

    expected_lines = [
        "[RETAIN] data_point_1",
        "[RETAIN] data_point_2",
        "[RETAIN] data_point_5",
        "[RETAIN] data_point_7"
    ]

    assert actual_lines == expected_lines, f"Contents of {OUTPUT_PATH} do not match the expected sorted output. Got: {actual_lines}"


def test_script_processes_altered_nested_data_and_symlink_loops():
    token = secrets.token_hex(12)

    shutil.rmtree(RAW_PATH)
    os.makedirs(os.path.join(RAW_PATH, 'alpha', 'nested'))
    os.makedirs(os.path.join(RAW_PATH, 'beta'))

    files = {
        os.path.join(RAW_PATH, 'alpha', 'first.dat'): [
            f'[RETAIN] zulu_{token}',
            f'[DROP] ignored_{token}',
            f'[RETAIN] alpha_{token}',
        ],
        os.path.join(RAW_PATH, 'alpha', 'nested', 'second.dat'): [
            f' [RETAIN] leading_space_{token}',
            f'[RETAIN] middle_{token}',
            f'[RETAINED] wrong_prefix_{token}',
        ],
        os.path.join(RAW_PATH, 'beta', 'third.dat'): [
            f'[RETAIN] alpha_{token}',
            f'[DROP] another_ignored_{token}',
        ],
        os.path.join(RAW_PATH, 'beta', 'not_data.txt'): [
            f'[RETAIN] wrong_extension_{token}',
        ],
        os.path.join(RAW_PATH, 'decoy.dat.bak'): [
            f'[RETAIN] wrong_suffix_{token}',
        ],
    }

    for path, lines in files.items():
        with open(path, 'w') as f:
            f.write('\n'.join(lines) + '\n')

    # Recursive directory links must not cause traversal to hang or duplicate data.
    os.symlink(RAW_PATH, os.path.join(RAW_PATH, 'alpha', 'nested', 'loop_to_root'))
    os.symlink(os.path.join(RAW_PATH, 'alpha'), os.path.join(RAW_PATH, 'beta', 'loop_to_alpha'))

    expected = []
    for directory, dirnames, filenames in os.walk(RAW_PATH, followlinks=False):
        for filename in filenames:
            if not filename.endswith('.dat'):
                continue
            path = os.path.join(directory, filename)
            if not os.path.isfile(path) or os.path.islink(path):
                continue
            with open(path, 'r') as f:
                expected.extend(line.rstrip('\n') for line in f if line.startswith('[RETAIN]'))
    expected.sort()

    if os.path.lexists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)

    run_script()

    assert os.path.isfile(OUTPUT_PATH), f"Script did not create {OUTPUT_PATH} on altered input."
    with open(OUTPUT_PATH, 'r') as f:
        actual = f.read().splitlines()

    assert actual == expected, (
        'Script did not safely traverse, filter, and sort the altered dataset. '
        f'Expected {expected!r}, got {actual!r}'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
