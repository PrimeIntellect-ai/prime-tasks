#!/bin/bash
mkdir -p /logs/verifier

# Terminate any agent-owned helper process that could continue serving the oracle.
pkill -KILL -u user 2>/dev/null || true

cat << 'SECCOMP_EOF' > /tmp/no_exec.c
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/filter.h>
#include <linux/seccomp.h>

__attribute__((constructor)) static void install_filter(void) {
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execve, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
#ifdef __NR_execveat
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execveat, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
#endif
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = {
        .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 ||
        prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) != 0) {
        _exit(125);
    }
}
SECCOMP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import numpy as np
import pytest

MODEL_PATH = "/home/user/reconstructed_model.py"
BINARY_PATH = "/app/sensor_encoder"
PRELOAD_PATH = "/tmp/no_exec.so"


def test_reconstructed_model_exists():
    assert os.path.exists(MODEL_PATH), f"Missing reconstructed model script: {MODEL_PATH}"
    assert os.path.isfile(MODEL_PATH), f"Path is not a file: {MODEL_PATH}"


def run_oracle(inputs):
    outputs = []
    for inp in inputs:
        args = [str(x) for x in inp]
        try:
            result = subprocess.run(
                [BINARY_PATH] + args,
                capture_output=True,
                text=True,
                check=True,
                timeout=5,
            )
            output = np.array([float(x) for x in result.stdout.strip().split()], dtype=np.float64)
            assert output.shape == (5,), f"Legacy binary returned {output.shape}, expected (5,)"
            assert np.all(np.isfinite(output)), "Legacy binary returned non-finite output"
            outputs.append(output)
        except Exception as exc:
            pytest.fail(f"Failed to run legacy binary on input {inp}: {exc}")
    return np.asarray(outputs)


def run_submission(inputs):
    outputs = []
    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD_PATH
    for inp in inputs:
        args = [str(x) for x in inp]
        result = None
        try:
            result = subprocess.run(
                ["python3", MODEL_PATH] + args,
                capture_output=True,
                text=True,
                check=True,
                timeout=5,
                env=env,
            )
            output = np.array([float(x) for x in result.stdout.strip().split()], dtype=np.float64)
            assert output.shape == (5,), f"Model returned {output.shape}, expected exactly 5 values"
            assert np.all(np.isfinite(output)), "Model returned non-finite output"
            outputs.append(output)
        except Exception as exc:
            stdout = result.stdout if result is not None else ""
            stderr = result.stderr if result is not None else ""
            pytest.fail(
                f"Failed to run reconstructed model on input {inp}: {exc}"
                f"\nStdout: {stdout}\nStderr: {stderr}"
            )
    return np.asarray(outputs)


def test_reconstructed_model_mse():
    assert os.path.exists(MODEL_PATH), f"Missing reconstructed model script: {MODEL_PATH}"
    assert os.path.exists(BINARY_PATH), f"Missing legacy tool binary: {BINARY_PATH}"
    assert os.path.isfile(PRELOAD_PATH), f"Missing execution sandbox: {PRELOAD_PATH}"

    # Preserve the original 1,000-vector assertion.
    np.random.seed(42)
    fixed_inputs = np.random.randn(1000, 10).astype(np.float32)

    # Add unpredictable held-out vectors that cannot be copied from raw_candidates.npy.
    raw = np.frombuffer(os.urandom(128 * 10 * 4), dtype=np.uint32).reshape(128, 10)
    random_inputs = ((raw.astype(np.float64) / np.float64(2**32 - 1)) * 40.0 - 20.0).astype(np.float32)

    fixed_true = run_oracle(fixed_inputs)
    random_true = run_oracle(random_inputs)

    # Keep the oracle only in verifier memory while evaluating the submission.
    oracle_bytes = open(BINARY_PATH, "rb").read()
    oracle_mode = stat.S_IMODE(os.stat(BINARY_PATH).st_mode)
    os.unlink(BINARY_PATH)

    try:
        fixed_pred = run_submission(fixed_inputs)
        random_pred = run_submission(random_inputs)
    finally:
        with open(BINARY_PATH, "wb") as restored:
            restored.write(oracle_bytes)
        os.chmod(BINARY_PATH, oracle_mode)

    threshold = 1e-10
    fixed_mse = np.mean((fixed_true - fixed_pred) ** 2)
    random_mse = np.mean((random_true - random_pred) ** 2)

    assert fixed_mse <= threshold, (
        f"MSE {fixed_mse} exceeds threshold {threshold}. "
        "Reconstructed model does not match legacy binary."
    )
    assert random_mse <= threshold, (
        f"Unpredictable-input MSE {random_mse} exceeds threshold {threshold}. "
        "Reconstructed model does not generalize as the recovered linear transform."
    )
TEST_EOF

if gcc -shared -fPIC -O2 -o /tmp/no_exec.so /tmp/no_exec.c && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
