#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

WRAPPER_PATH = "/home/user/sanitize_wrapper.sh"
EVIL_CORPUS_DIR = "/app/corpus/evil/"
CLEAN_CORPUS_DIR = "/app/corpus/clean/"
BINARY_PATH = "/app/bin/spec_deconv"


def run_wrapper(filepath, timeout=5):
    return subprocess.run(
        [WRAPPER_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_wrapper_exists_and_executable():
    assert os.path.exists(WRAPPER_PATH), f"Wrapper script not found at {WRAPPER_PATH}"
    assert os.path.isfile(WRAPPER_PATH), f"{WRAPPER_PATH} is not a file"
    assert os.access(WRAPPER_PATH, os.X_OK), f"Wrapper script at {WRAPPER_PATH} is not executable"


def test_evil_corpus_rejected():
    assert os.path.exists(EVIL_CORPUS_DIR), f"Evil corpus dir missing: {EVIL_CORPUS_DIR}"
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert evil_files, "No files found in evil corpus"

    bypassed = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_CORPUS_DIR, filename)
        try:
            result = run_wrapper(filepath)
            if result.returncode != 1 or result.stdout.strip() != "REJECT":
                bypassed.append(filename)
        except subprocess.TimeoutExpired:
            bypassed.append(f"{filename} (timeout)")

    if bypassed:
        pytest.fail(f"{len(bypassed)} of {len(evil_files)} evil files bypassed rejection. Offending files: {', '.join(bypassed)}")


def test_clean_corpus_preserved():
    assert os.path.exists(CLEAN_CORPUS_DIR), f"Clean corpus dir missing: {CLEAN_CORPUS_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert clean_files, "No files found in clean corpus"

    modified_or_failed = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_CORPUS_DIR, filename)
        expected_result = subprocess.run(
            [BINARY_PATH, filepath],
            capture_output=True,
            text=True,
            timeout=5,
        )

        try:
            wrapper_result = run_wrapper(filepath)
            if wrapper_result.returncode != 0:
                modified_or_failed.append(f"{filename} (exit code {wrapper_result.returncode})")
            elif wrapper_result.stdout.strip() == "REJECT":
                modified_or_failed.append(f"{filename} (falsely rejected)")
            elif wrapper_result.stdout != expected_result.stdout:
                modified_or_failed.append(f"{filename} (stdout mismatch)")
        except subprocess.TimeoutExpired:
            modified_or_failed.append(f"{filename} (timeout)")

    if modified_or_failed:
        pytest.fail(f"{len(modified_or_failed)} of {len(clean_files)} clean files failed or modified. Offending files: {', '.join(modified_or_failed)}")


def write_signal(path, values):
    with open(path, "w") as f:
        for value in values:
            f.write(f"{value:.12f}\n")


def test_fresh_path_independent_signals():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    failures = []

    with tempfile.TemporaryDirectory(prefix="signals_") as signal_dir:
        cases = []
        for _ in range(16):
            # Every value lies within a width-four interval, so every ten-sample
            # population variance is safely below the divergence boundary.
            center = rng.uniform(-200.0, 200.0)
            values = [center + rng.uniform(-2.0, 2.0) for _ in range(rng.randint(40, 180))]
            cases.append((False, values))

        for _ in range(16):
            length = rng.randint(40, 180)
            center = rng.uniform(-200.0, 200.0)
            values = [center + rng.uniform(-1.0, 1.0) for _ in range(length)]
            start = rng.randint(0, length - 10)
            amplitude = rng.uniform(18.0, 60.0)
            for j in range(10):
                values[start + j] = center + (amplitude if j % 2 else -amplitude)
            cases.append((True, values))

        rng.shuffle(cases)
        for index, (must_reject, values) in enumerate(cases):
            filepath = os.path.join(signal_dir, f"{secrets.token_hex(10)}_{index}.dat")
            write_signal(filepath, values)

            if must_reject:
                try:
                    result = run_wrapper(filepath)
                    if result.returncode != 1 or result.stdout.strip() != "REJECT":
                        failures.append(f"generated case {index} was not rejected")
                except subprocess.TimeoutExpired:
                    failures.append(f"generated case {index} timed out")
            else:
                expected = subprocess.run(
                    [BINARY_PATH, filepath],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                try:
                    result = run_wrapper(filepath)
                    if result.returncode != 0:
                        failures.append(f"generated case {index} exited {result.returncode}")
                    elif result.stdout.strip() == "REJECT":
                        failures.append(f"generated case {index} was falsely rejected")
                    elif result.stdout != expected.stdout:
                        failures.append(f"generated case {index} changed binary stdout")
                except subprocess.TimeoutExpired:
                    failures.append(f"generated case {index} timed out")

    if failures:
        pytest.fail("; ".join(failures))


def test_safe_input_is_passed_to_binary():
    token = secrets.token_hex(16)
    marker = f"binary-invoked-{token}"
    backup = f"{BINARY_PATH}.verifier-{token}"
    log_path = os.path.join(tempfile.gettempdir(), f"spec-call-{token}.log")

    fd, signal_path = tempfile.mkstemp(prefix="neutral_", suffix=".txt")
    os.close(fd)
    write_signal(signal_path, [1.0 + (i % 3) * 0.1 for i in range(60)])

    os.replace(BINARY_PATH, backup)
    try:
        with open(BINARY_PATH, "w") as shim:
            shim.write("#!/bin/sh\n")
            shim.write(f"printf '%s\\n' \"$#\" > {log_path!r}\n")
            shim.write(f"printf '%s\\n' \"$1\" >> {log_path!r}\n")
            shim.write(f"printf '%s\\n' {marker!r}\n")
        os.chmod(BINARY_PATH, 0o755)

        result = run_wrapper(signal_path)
        assert result.returncode == 0, "Wrapper rejected or failed a safe signal during binary invocation check"
        assert result.stdout == marker + "\n", "Wrapper did not forward the invoked binary's stdout"
        assert os.path.exists(log_path), "Wrapper did not invoke /app/bin/spec_deconv"
        with open(log_path) as log:
            call = log.read().splitlines()
        assert call == ["1", signal_path], "Wrapper did not pass exactly the supplied signal path to the binary"
    finally:
        if os.path.lexists(BINARY_PATH):
            os.unlink(BINARY_PATH)
        os.replace(backup, BINARY_PATH)
        if os.path.exists(signal_path):
            os.unlink(signal_path)
        if os.path.exists(log_path):
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
