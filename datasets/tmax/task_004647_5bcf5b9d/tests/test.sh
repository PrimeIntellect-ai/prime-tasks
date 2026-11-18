#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any agent-owned helper process that could proxy calls to a previously
# copied oracle during verification.
pkill -9 -u user 2>/dev/null || true

WORKDIR=$(mktemp -d /tmp/verifier.XXXXXX)
chmod 755 "$WORKDIR"
trap 'chmod 755 /app/oracle_processor 2>/dev/null || true; rm -rf "$WORKDIR"' EXIT

cat << 'RUNNER_EOF' > "$WORKDIR/restricted_runner.py"
import ctypes
import os
import pwd
import runpy
import sys

# Linux seccomp filter: deny execve and execveat after this Python interpreter
# has started, preventing the submitted script or its children from executing
# a copied oracle or any other subprocess.
PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2
SECCOMP_RET_ALLOW = 0x7FFF0000
SECCOMP_RET_ERRNO = 0x00050000
EPERM = 1
BPF_LD = 0x00
BPF_W = 0x00
BPF_ABS = 0x20
BPF_JMP = 0x05
BPF_JEQ = 0x10
BPF_K = 0x00
BPF_RET = 0x06
SYS_EXECVE = 59
SYS_EXECVEAT = 322

class SockFilter(ctypes.Structure):
    _fields_ = [
        ('code', ctypes.c_ushort),
        ('jt', ctypes.c_ubyte),
        ('jf', ctypes.c_ubyte),
        ('k', ctypes.c_uint32),
    ]

class SockFprog(ctypes.Structure):
    _fields_ = [
        ('len', ctypes.c_ushort),
        ('filter', ctypes.POINTER(SockFilter)),
    ]

filters = (SockFilter * 6)(
    SockFilter(BPF_LD | BPF_W | BPF_ABS, 0, 0, 0),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, SYS_EXECVE),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EPERM),
    SockFilter(BPF_JMP | BPF_JEQ | BPF_K, 0, 1, SYS_EXECVEAT),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ERRNO | EPERM),
    SockFilter(BPF_RET | BPF_K, 0, 0, SECCOMP_RET_ALLOW),
)
program = SockFprog(len(filters), filters)
libc = ctypes.CDLL(None, use_errno=True)

if len(sys.argv) != 4:
    raise SystemExit(2)
script, input_path, output_path = sys.argv[1:]

account = pwd.getpwnam('user')
os.setgroups([])
os.setgid(account.pw_gid)
os.setuid(account.pw_uid)

if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), 'PR_SET_NO_NEW_PRIVS failed')
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.byref(program)) != 0:
    raise OSError(ctypes.get_errno(), 'PR_SET_SECCOMP failed')

sys.argv = [script, input_path, output_path]
sys.path.insert(0, os.path.dirname(script))
runpy.run_path(script, run_name='__main__')
RUNNER_EOF
chmod 755 "$WORKDIR/restricted_runner.py"
export VERIFIER_RUNNER="$WORKDIR/restricted_runner.py"

cat << 'TEST_EOF' > "$WORKDIR/test_final_state.py"
import os
import stat
import subprocess
import secrets
import numpy as np
import h5py
import pytest


def test_fast_prepare_mse():
    agent_script = '/home/user/fast_prepare.py'
    oracle = '/app/oracle_processor'
    runner = os.environ['VERIFIER_RUNNER']

    assert os.path.exists(agent_script), f'Agent script {agent_script} does not exist.'
    assert os.path.isfile(agent_script), f'Agent script {agent_script} is not a regular file.'

    # Use fresh, unpredictable held-out inputs so test-specific output
    # hardcoding cannot pass. Expected answers are produced before the oracle
    # is made inaccessible to the submitted program.
    rng = np.random.default_rng(secrets.randbits(128))
    cases = []
    for index, rows in enumerate((2000, 1379)):
        raw = rng.standard_normal((rows, 50)) @ rng.standard_normal((50, 50))
        if index == 0:
            input_path = '/tmp/test_raw.h5'
            reference_path = '/tmp/reference_processed.h5'
            output_path = '/home/user/test_processed.h5'
        else:
            input_path = f'/tmp/test_raw_{index}.h5'
            reference_path = f'/tmp/reference_processed_{index}.h5'
            output_path = f'/home/user/test_processed_{index}.h5'

        for path in (input_path, reference_path, output_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        with h5py.File(input_path, 'w') as f:
            f.create_dataset('raw_features', data=raw)
        os.chmod(input_path, 0o644)

        try:
            subprocess.run(
                [oracle, input_path, reference_path],
                check=True,
                capture_output=True,
                text=True,
            )
        except subprocess.CalledProcessError as e:
            pytest.fail(f'Oracle processor failed to run: {e.stderr}')
        cases.append((input_path, reference_path, output_path))

    original_mode = stat.S_IMODE(os.stat(oracle).st_mode)
    os.chmod(oracle, 0)
    try:
        for input_path, reference_path, output_path in cases:
            try:
                subprocess.run(
                    ['python3', runner, agent_script, input_path, output_path],
                    check=True,
                    capture_output=True,
                    text=True,
                )
            except subprocess.CalledProcessError as e:
                pytest.fail(
                    f'Agent script failed to run: stdout={e.stdout!r}, stderr={e.stderr!r}'
                )

            assert os.path.exists(output_path), (
                f'Agent output file {output_path} was not created.'
            )

            with h5py.File(reference_path, 'r') as f:
                ref_data = f['clean_features'][:]

            with h5py.File(output_path, 'r') as f:
                assert 'clean_features' in f, (
                    "Dataset 'clean_features' not found in agent's output HDF5 file."
                )
                agent_data = f['clean_features'][:]

            assert ref_data.shape == agent_data.shape, (
                f'Shape mismatch: expected {ref_data.shape}, got {agent_data.shape}'
            )

            mse = np.mean((ref_data - agent_data) ** 2)
            assert mse <= 0.005, (
                f'MSE {mse:.6f} is greater than the threshold of 0.005.'
            )
    finally:
        os.chmod(oracle, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORKDIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
