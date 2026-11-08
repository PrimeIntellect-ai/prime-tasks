#!/bin/bash
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

workdir=$(mktemp -d /tmp/secure-auth-verifier.XXXXXX) || exit 0
chmod 700 "$workdir"
trap 'rm -rf "$workdir"' EXIT

cat > "$workdir/runner.py" <<'PY_EOF'
import ctypes
import errno
import runpy
import sys

class SockFilter(ctypes.Structure):
    _fields_ = [
        ("code", ctypes.c_ushort),
        ("jt", ctypes.c_ubyte),
        ("jf", ctypes.c_ubyte),
        ("k", ctypes.c_uint),
    ]

class SockFprog(ctypes.Structure):
    _fields_ = [
        ("len", ctypes.c_ushort),
        ("filter", ctypes.POINTER(SockFilter)),
    ]

# Prevent the submitted Python program from delegating token generation to any
# copied executable. The interpreter is already running when this filter is set.
BPF_LD_W_ABS = 0x20
BPF_JMP_JEQ_K = 0x15
BPF_RET_K = 0x06
SECCOMP_RET_ERRNO = 0x00050000
SECCOMP_RET_ALLOW = 0x7fff0000
SYS_EXECVE = 59
SYS_EXECVEAT = 322

filters = (SockFilter * 6)(
    SockFilter(BPF_LD_W_ABS, 0, 0, 0),
    SockFilter(BPF_JMP_JEQ_K, 0, 1, SYS_EXECVE),
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_JMP_JEQ_K, 0, 1, SYS_EXECVEAT),
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ERRNO | errno.EPERM),
    SockFilter(BPF_RET_K, 0, 0, SECCOMP_RET_ALLOW),
)
program = SockFprog(len(filters), filters)
libc = ctypes.CDLL(None, use_errno=True)

PR_SET_NO_NEW_PRIVS = 38
PR_SET_SECCOMP = 22
SECCOMP_MODE_FILTER = 2

if libc.prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ctypes.addressof(program), 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")

script = sys.argv[1]
sys.argv = [script] + sys.argv[2:]
runpy.run_path(script, run_name="__main__")
PY_EOF

cat > "$workdir/test_final_state.py" <<'PY_EOF'
import os
import secrets
import string
import subprocess

from Crypto.Cipher import AES
from Crypto.Util.Padding import pad

ALPHABET = string.ascii_letters + string.digits
KEY = b"d3vS3c0ps_k3y123"


def rand_string(length):
    return ''.join(secrets.choice(ALPHABET) for _ in range(length))


def expected_token(user, password):
    plaintext = f"{user}:{password}".encode()
    ciphertext = AES.new(KEY, AES.MODE_ECB).encrypt(pad(plaintext, AES.block_size))
    return "TOKEN: " + ciphertext.hex()


def test_secure_auth_accuracy():
    script_path = "/home/user/secure_auth.py"
    binary_path = "/app/legacy_auth"
    runner_path = os.environ["SECURE_AUTH_RUNNER"]

    assert os.path.exists(script_path), f"Script not found at {script_path}"
    assert os.path.isfile(script_path), f"Submission is not a regular file: {script_path}"
    assert os.path.exists(binary_path), f"Binary not found at {binary_path}"

    # The binary was available during the analysis phase, but must not remain
    # callable by the submitted program while its behavior is being tested.
    os.unlink(binary_path)

    matches = 0
    total = 100
    for _ in range(total):
        user = rand_string(secrets.randbelow(9) + 4)
        password = rand_string(secrets.randbelow(13) + 8)
        expected = expected_token(user, password)

        try:
            actual = subprocess.check_output(
                ["python3", "-I", runner_path, script_path, user, password],
                text=True,
                stderr=subprocess.STDOUT,
                timeout=10,
            ).strip()
        except subprocess.CalledProcessError as exc:
            raise AssertionError(f"Python script failed. Output: {exc.output}") from exc
        except subprocess.TimeoutExpired as exc:
            raise AssertionError("Python script timed out") from exc

        assert actual == expected, (
            f"Mismatch for user={user!r}, pwd={password!r}. "
            f"Expected: {expected!r}, Actual: {actual!r}"
        )
        matches += 1

    accuracy = matches / total
    assert accuracy >= 1.0, f"Accuracy: {accuracy}. Expected >= 1.0"
PY_EOF

# Remove any background process left by the interactive user that could act as
# an oracle during verification.
pkill -KILL -u user >/dev/null 2>&1 || true

if SECURE_AUTH_RUNNER="$workdir/runner.py" python3 -m pytest "$workdir/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
