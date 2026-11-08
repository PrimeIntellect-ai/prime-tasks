#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import time

BINARY_PATH = "/home/user/parser/parser"


def run_parser(input_path, output_path, timeout=3):
    return subprocess.run(
        [BINARY_PATH, input_path, output_path],
        capture_output=True,
        timeout=timeout,
    )


def test_parser_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"Compiled binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The parser must be a compiled binary"


def test_execution_time_and_accuracy():
    input_path = "/app/mem_dump.bin"
    output_path = "/home/user/extracted_strings.txt"
    expected_strings = "\n".join(f"ValidString_{i}" for i in range(50))

    if os.path.exists(output_path):
        os.remove(output_path)

    start_time = time.perf_counter()
    res = run_parser(input_path, output_path)
    elapsed = time.perf_counter() - start_time

    assert res.returncode == 0, (
        f"Parser failed with return code {res.returncode}. "
        f"Stderr: {res.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(output_path), f"Output file not created at {output_path}"

    with open(output_path, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_strings, (
        "The extracted strings do not match the expected output. Ensure the "
        "delimiter, offset, and bounds checking are correct."
    )

    threshold = 0.2
    assert elapsed <= threshold, (
        f"Execution time {elapsed:.4f}s exceeded the threshold of {threshold}s. "
        "The I/O operations are likely still inefficient."
    )


def test_parser_on_unseen_records_and_truncated_eof():
    # Generate answers unavailable in the image. A complete 255-byte record is
    # valid, while the final record is genuinely truncated at EOF and must not
    # be emitted or read out of bounds.
    strings = [
        ("alpha_" + secrets.token_hex(7)).encode(),
        ("middle_" + secrets.token_hex(19)).encode(),
        b"Q" * 255,
        ("tail_" + secrets.token_hex(11)).encode(),
    ]

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "unseen_dump.bin")
        output_path = os.path.join(td, "unseen_output.txt")

        with open(input_path, "wb") as f:
            f.write(b"unrelated-prefix-and-partial-#DAT-noise")
            for i, value in enumerate(strings):
                f.write(b"#DATA#")
                f.write(secrets.token_bytes(4))
                f.write(bytes([len(value)]))
                f.write(value)
                f.write((b"garbage" + bytes([65 + i])) * 13)

            f.write(b"#DATA#")
            f.write(secrets.token_bytes(4))
            f.write(bytes([255]))
            f.write(b"truncated-at-eof")

        res = run_parser(input_path, output_path)
        assert res.returncode == 0, (
            f"Parser failed on an unseen valid dump with return code "
            f"{res.returncode}. Stderr: "
            f"{res.stderr.decode('utf-8', errors='replace')}"
        )
        assert os.path.isfile(output_path), "Parser did not create the requested output file"

        with open(output_path, "rb") as f:
            actual = f.read()
        expected = b"".join(value + b"\n" for value in strings)
        assert actual == expected, (
            "Parser failed to extract unseen records correctly or emitted the "
            "truncated EOF record"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
