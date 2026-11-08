#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import random
import stat
import struct
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/legacy_processor"
AGENT_PATH = "/home/user/replacement.py"
N_ITERATIONS = 1000


def generate_random_chunk():
    choice = random.randint(0, 5)
    if choice == 0:
        return struct.pack('<f', random.uniform(-1000.0, 1000.0))
    elif choice == 1:
        return b'\xff\xff\xff\xff'
    elif choice == 2:
        return struct.pack('<f', float('nan'))
    elif choice == 3:
        return struct.pack('<f', float('inf'))
    elif choice == 4:
        return struct.pack('<f', float('-inf'))
    return bytes([random.randint(0, 255) for _ in range(4)])


def file_digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(65536), b''):
            h.update(block)
    return h.digest()


def demote_to_user():
    account = pwd.getpwnam('user')
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_replacement_script_exists():
    assert os.path.exists(AGENT_PATH), f"Replacement script not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"Replacement script at {AGENT_PATH} is not executable"
    assert file_digest(AGENT_PATH) != file_digest(ORACLE_PATH), \
        "Replacement must not be a byte-identical copy of the legacy binary"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary at {ORACLE_PATH} is not executable"

    # Build an independent test-only evaluator. Its directory is root-only, so the
    # submitted program cannot delegate its work to this evaluator.
    evaluator_dir = tempfile.mkdtemp(prefix='verifier-evaluator-')
    os.chmod(evaluator_dir, 0o700)
    source_path = os.path.join(evaluator_dir, 'evaluator.c')
    evaluator_path = os.path.join(evaluator_dir, 'evaluator')
    source = r'''
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    float sum = 0.0f;
    int counter = 0;
    uint32_t chunk;
    while (fread(&chunk, 4, 1, f) == 1) {
        if (chunk == UINT32_C(0xFFFFFFFF)) {
            counter++;
            if (counter == 3) {
                sum = 0.0f;
                counter = 0;
            }
        } else {
            float value;
            memcpy(&value, &chunk, sizeof(value));
            if (isnan(value) || isinf(value))
                continue;
            sum += value;
        }
    }
    fclose(f);
    float result = sum * sum;
    printf("%.6f\n", result);
    return 0;
}
'''
    with open(source_path, 'w') as f:
        f.write(source)
    subprocess.run(
        ['gcc', '-O0', source_path, '-lm', '-o', evaluator_path],
        check=True, capture_output=True, text=True
    )
    os.chmod(evaluator_path, 0o700)

    random.seed(42)
    original_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)

    with tempfile.TemporaryDirectory(prefix='verifier-inputs-') as tmpdir:
        # The unprivileged candidate may read inputs but cannot replace them.
        os.chmod(tmpdir, 0o755)
        cases = []

        for i in range(N_ITERATIONS):
            num_chunks = random.randint(1, 256)
            data = b''.join(generate_random_chunk() for _ in range(num_chunks))
            input_file = os.path.join(tmpdir, f'input-{i}.bin')
            with open(input_file, 'wb') as f:
                f.write(data)
            os.chmod(input_file, 0o644)

            try:
                oracle_result = subprocess.run(
                    [ORACLE_PATH, input_file], capture_output=True,
                    text=True, timeout=2
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Oracle timed out on input iteration {i}")

            expected = subprocess.run(
                [evaluator_path, input_file], capture_output=True,
                text=True, timeout=2
            )
            assert oracle_result.returncode == expected.returncode, \
                f"Legacy/evaluator return code disagreement on iteration {i}"
            assert oracle_result.stdout.strip() == expected.stdout.strip(), \
                f"Legacy/evaluator output disagreement on iteration {i}"
            cases.append((input_file, data, oracle_result.returncode,
                          oracle_result.stdout.strip()))

        # Make the legacy executable unavailable, then run the candidate as the
        # unprivileged user. A wrapper that execs /app/legacy_processor now fails.
        os.chmod(ORACLE_PATH, 0)
        try:
            for i, (input_file, data, oracle_rc, oracle_stdout) in enumerate(cases):
                try:
                    agent_result = subprocess.run(
                        [AGENT_PATH, input_file], capture_output=True,
                        text=True, timeout=2, preexec_fn=demote_to_user
                    )
                except subprocess.TimeoutExpired:
                    pytest.fail(f"Agent script timed out on input iteration {i}")

                agent_stdout = agent_result.stdout.strip()
                assert agent_result.returncode == oracle_rc, \
                    f"Return code mismatch on iteration {i}. Oracle: {oracle_rc}, Agent: {agent_result.returncode}"
                assert agent_stdout == oracle_stdout, \
                    f"Output mismatch on iteration {i}!\nInput hex: {data.hex()}\nOracle output: {oracle_stdout}\nAgent output: {agent_stdout}"
        finally:
            os.chmod(ORACLE_PATH, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
