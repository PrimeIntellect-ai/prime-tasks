#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import subprocess

PACKAGE_DIR = "/app/libprime-1.0.0"
BINARY_PATH = os.path.join(PACKAGE_DIR, "prime")
AGENT_SCRIPT = "/app/prime_encoder.sh"


def generate_primes(count):
    primes = []
    candidate = 2
    while len(primes) < count:
        is_prime = True
        for divisor in primes:
            if divisor * divisor > candidate:
                break
            if candidate % divisor == 0:
                is_prime = False
                break
        if is_prime:
            primes.append(candidate)
        candidate += 1
    return primes


def test_make_builds_prime_binary():
    assert os.path.isfile(os.path.join(PACKAGE_DIR, "Makefile")), "Makefile is missing."

    if os.path.lexists(BINARY_PATH):
        assert not os.path.isdir(BINARY_PATH), f"{BINARY_PATH} must not be a directory."
        os.unlink(BINARY_PATH)

    proc = subprocess.run(
        ["make"],
        cwd=PACKAGE_DIR,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert proc.returncode == 0, f"make failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"

    assert os.path.isfile(BINARY_PATH), f"The binary {BINARY_PATH} was not built."
    assert os.access(BINARY_PATH, os.X_OK), f"The binary {BINARY_PATH} is not executable."


def test_prime_binary_results():
    inputs = [1, 2, 3, 10, 100, 1000]
    primes = generate_primes(max(inputs))

    for n in inputs:
        proc = subprocess.run(
            [BINARY_PATH, str(n)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert proc.returncode == 0, f"prime failed on input {n}: {proc.stderr}"
        assert proc.stdout == str(primes[n - 1]), (
            f"prime returned the wrong result for input {n}: {proc.stdout!r}"
        )


def test_wrapper_calls_prime_with_exact_input():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

    saved_binary = BINARY_PATH + ".verifier-saved"
    probe_log = "/tmp/prime_probe_args"
    if os.path.exists(probe_log):
        os.unlink(probe_log)

    os.rename(BINARY_PATH, saved_binary)
    try:
        with open(BINARY_PATH, "w", encoding="utf-8") as probe:
            probe.write("#!/bin/sh\nprintf '%s\\n' \"$@\" >> /tmp/prime_probe_args\nprintf '424242'\n")
        os.chmod(BINARY_PATH, 0o755)

        proc = subprocess.run(
            [AGENT_SCRIPT, "7"],
            capture_output=True,
            text=False,
            timeout=10,
        )
        assert proc.returncode == 0, f"Agent script failed with probe binary: {proc.stderr!r}"
        assert proc.stdout == base64.b64encode(b"PRIME:424242"), (
            f"Wrapper serialization is incorrect: {proc.stdout!r}"
        )
        with open(probe_log, "r", encoding="utf-8") as logged:
            assert logged.read() == "7\n", "Wrapper did not call prime exactly once with the original N."
    finally:
        if os.path.lexists(BINARY_PATH):
            os.unlink(BINARY_PATH)
        os.rename(saved_binary, BINARY_PATH)


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

    random.seed(42)
    inputs = [random.randint(1, 10000) for _ in range(100)]
    primes = generate_primes(max(inputs))

    for n in inputs:
        expected = base64.b64encode(f"PRIME:{primes[n - 1]}".encode("ascii"))
        proc = subprocess.run(
            [AGENT_SCRIPT, str(n)],
            capture_output=True,
            text=False,
            timeout=10,
        )
        assert proc.returncode == 0, f"Agent script failed on input {n}: {proc.stderr!r}"
        assert proc.stdout == expected, (
            f"Mismatch on input {n}. Expected {expected!r}, got {proc.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
