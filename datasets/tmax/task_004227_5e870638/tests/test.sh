#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import base64
import hashlib
import time
import subprocess
import tempfile


def test_fast_credgen_exists():
    assert os.path.exists("/home/user/fast_credgen.c"), "Source file /home/user/fast_credgen.c is missing"
    assert os.path.exists("/home/user/fast_credgen"), "Compiled binary /home/user/fast_credgen is missing"
    assert os.access("/home/user/fast_credgen", os.X_OK), "Compiled binary /home/user/fast_credgen is not executable"
    with open("/home/user/fast_credgen", "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled program /home/user/fast_credgen is not an ELF binary"


def expected_for(lines):
    return "".join(
        hashlib.sha256(base64.b64decode(line) + b"!SecR0t@t1on#").hexdigest() + "\n"
        for line in lines
    )


def test_unseen_inputs_and_source_implementation():
    # Generate inputs only after the agent has finished, so the executable cannot
    # pass by replaying the submitted rotated_creds.txt file.
    lines = [base64.b64encode(os.urandom(16)).decode("ascii") for _ in range(512)]
    expected = expected_for(lines)

    with tempfile.TemporaryDirectory(prefix="credgen_verify_") as td:
        input_path = os.path.join(td, "random_seeds.txt")
        binary_output = os.path.join(td, "binary_output.txt")
        rebuilt_output = os.path.join(td, "rebuilt_output.txt")
        rebuilt_binary = os.path.join(td, "rebuilt_fast_credgen")

        with open(input_path, "w") as f:
            f.write("\n".join(lines) + "\n")

        result = subprocess.run(
            ["/home/user/fast_credgen", input_path, binary_output],
            capture_output=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"fast_credgen failed on unseen inputs with return code {result.returncode}\n"
            f"Stderr: {result.stderr.decode(errors='replace')}"
        )
        assert os.path.exists(binary_output), "fast_credgen did not create output for unseen inputs"
        with open(binary_output, "r") as f:
            assert f.read() == expected, "fast_credgen produced incorrect results for unseen inputs"

        compile_result = subprocess.run(
            ["gcc", "-O3", "-o", rebuilt_binary, "/home/user/fast_credgen.c", "-lcrypto"],
            capture_output=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "fast_credgen.c could not be compiled:\n"
            + compile_result.stderr.decode(errors="replace")
        )

        rebuilt_result = subprocess.run(
            [rebuilt_binary, input_path, rebuilt_output],
            capture_output=True,
            timeout=10,
        )
        assert rebuilt_result.returncode == 0, (
            f"Program rebuilt from fast_credgen.c failed with return code {rebuilt_result.returncode}\n"
            f"Stderr: {rebuilt_result.stderr.decode(errors='replace')}"
        )
        assert os.path.exists(rebuilt_output), "Program rebuilt from fast_credgen.c did not create output"
        with open(rebuilt_output, "r") as f:
            assert f.read() == expected, "fast_credgen.c does not implement the required logic on unseen inputs"


def test_correctness():
    assert os.path.exists("/home/user/rotated_creds.txt"), "Output file /home/user/rotated_creds.txt is missing"

    # Compute expected output based on the ground truth algorithm
    expected_lines = []
    with open("/app/seeds.txt", "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Decode base64
            decoded = base64.b64decode(line)
            # Append static salt
            combined = decoded + b"!SecR0t@t1on#"
            # Compute SHA-256 hash
            h = hashlib.sha256(combined).hexdigest()
            expected_lines.append(h)

    expected_content = "\n".join(expected_lines) + "\n"

    with open("/home/user/rotated_creds.txt", "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, "The generated credentials in /home/user/rotated_creds.txt do not match the expected output"


def test_performance():
    # Measure performance of the compiled C program
    start = time.perf_counter()
    result = subprocess.run(["/home/user/fast_credgen", "/app/seeds.txt", "/tmp/test_out.txt"], capture_output=True)
    duration = time.perf_counter() - start

    assert result.returncode == 0, f"fast_credgen failed with return code {result.returncode}\nStderr: {result.stderr.decode()}"

    # Verify the output produced during the performance test is also correct
    assert os.path.exists("/tmp/test_out.txt"), "fast_credgen did not create the output file during the performance test"

    with open("/tmp/test_out.txt", "r") as f:
        actual_test_content = f.read()

    with open("/home/user/rotated_creds.txt", "r") as f:
        expected_test_content = f.read()

    assert actual_test_content == expected_test_content, "The generated credentials during the performance test do not match the expected output"

    # Check against the 0.25 seconds threshold
    assert duration <= 0.25, f"Execution time {duration:.4f}s exceeded the 0.25s threshold"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
