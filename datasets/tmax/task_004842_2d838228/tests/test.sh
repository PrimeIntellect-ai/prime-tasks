#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'SECCOMP_EOF' > /tmp/no_exec.c
#define _GNU_SOURCE
#include <stddef.h>
#include <errno.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/filter.h>
#include <linux/seccomp.h>

__attribute__((constructor))
static void install_filter(void) {
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
        _exit(126);
    }
}
SECCOMP_EOF

gcc -shared -fPIC -O2 /tmp/no_exec.c -o /tmp/no_exec.so

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import subprocess
import tempfile
import numpy as np

SCRIPT_PATH = '/home/user/event_pipeline/fast_pipeline.py'
INPUT_FILE = '/home/user/data/events.bin'
OUTPUT_FILE = '/home/user/event_pipeline/output.bin'
LEGACY_ENGINE = '/app/legacy_engine'
NO_EXEC_LIBRARY = '/tmp/no_exec.so'


def restricted_environment():
    env = os.environ.copy()
    previous = env.get('LD_PRELOAD')
    env['LD_PRELOAD'] = NO_EXEC_LIBRARY if not previous else NO_EXEC_LIBRARY + ':' + previous
    return env


def run_submission(input_path, output_path, timeout=15):
    return subprocess.run(
        ['python3', SCRIPT_PATH, input_path, output_path],
        capture_output=True,
        text=True,
        env=restricted_environment(),
        timeout=timeout,
    )


def derive_expected(data):
    values = np.frombuffer(data, dtype=np.int16)
    assert values.size % 16 == 0
    frames = values.reshape(-1, 16)
    output = frames[frames[:, 0] != -1].copy()
    nonpositive = output <= 0
    output[nonpositive] = np.trunc(
        output[nonpositive].astype(np.float64) / 2.0
    ).astype(np.int16)
    return output.tobytes()


def test_fast_pipeline():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    # Obtain the canonical oracle result before running untrusted code, so the
    # submission cannot replace or modify the oracle and influence comparison.
    with open(INPUT_FILE, 'rb') as source:
        legacy_result = subprocess.run(
            [LEGACY_ENGINE], stdin=source, capture_output=True, timeout=15
        )
        try:
            os.posix_fadvise(source.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)
        except (AttributeError, OSError):
            pass

    assert legacy_result.returncode == 0, (
        f"Legacy engine failed to process input. Stderr: {legacy_result.stderr}"
    )
    expected_output = legacy_result.stdout

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    # The seccomp preload permits normal Python/native-library operation but
    # prevents this process from executing the legacy engine or a copied binary.
    start_time = time.time()
    result = run_submission(INPUT_FILE, OUTPUT_FILE)
    end_time = time.time()
    runtime = end_time - start_time

    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), f"Output file not created at {OUTPUT_FILE}"

    with open(OUTPUT_FILE, 'rb') as output:
        actual_output = output.read()

    expected_array = np.frombuffer(expected_output, dtype=np.int16)
    actual_array = np.frombuffer(actual_output, dtype=np.int16)

    assert len(expected_array) == len(actual_array), (
        f"Output length mismatch: expected {len(expected_array)} elements, "
        f"got {len(actual_array)} elements"
    )

    if len(expected_array) > 0:
        mse = np.mean(
            (expected_array.astype(np.float64) - actual_array.astype(np.float64)) ** 2
        )
    else:
        mse = 0.0

    assert mse == 0.0, f"Output MSE vs reference is {mse}, expected 0.0"
    assert actual_output == expected_output, "Output does not exactly match the reference"
    assert runtime < 1.5, (
        f"Runtime speed is {runtime:.3f} seconds, expected < 1.5 seconds"
    )

    # Exercise the implementation on verifier-generated data that was not
    # available during the agent phase. Expected results are derived directly.
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), 'little'))
    frames = rng.integers(-32768, 32768, size=(8192, 16), dtype=np.int16)
    frames[::7, 0] = -1
    frames[1, :] = np.array(
        [-32768, -32767, -3, -2, -1, 0, 1, 2,
         32767, -9, 9, -100, 100, -5, 5, 42],
        dtype=np.int16,
    )
    fresh_input = frames.tobytes()
    fresh_expected = derive_expected(fresh_input)

    with tempfile.TemporaryDirectory(prefix='pipeline-check-') as directory:
        input_path = os.path.join(directory, 'events.bin')
        output_path = os.path.join(directory, 'output.bin')
        with open(input_path, 'wb') as stream:
            stream.write(fresh_input)

        fresh_result = run_submission(input_path, output_path, timeout=10)
        assert fresh_result.returncode == 0, (
            f"Script failed on verifier-generated input with return code "
            f"{fresh_result.returncode}. Stderr: {fresh_result.stderr}"
        )
        assert os.path.isfile(output_path), (
            "Output file was not created for verifier-generated input"
        )
        with open(output_path, 'rb') as stream:
            fresh_actual = stream.read()

        assert fresh_actual == fresh_expected, (
            "Incorrect output for verifier-generated valid and corrupted frames"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
