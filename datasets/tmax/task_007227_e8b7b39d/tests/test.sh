#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_joined_features_exists_and_content():
    path = "/home/user/joined_features.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "1 2.0 0.5",
        "2 3.5 1.0",
        "3 1.0 -1.0",
        "4 0.0 -1.5",
        "5 -2.0 3.0"
    ]

    # We allow variable whitespace between columns as long as the values match
    parsed_lines = [line.split() for line in lines]
    parsed_expected = [line.split() for line in expected]

    assert parsed_lines == parsed_expected, f"Content of {path} does not match the expected joined and sorted output."


def test_predictions_log_exists_and_content():
    path = "/home/user/predictions.log"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "1,2.85",
        "2,4.85",
        "3,2.10",
        "4,0.85",
        "5,-4.40"
    ]

    assert lines == expected, f"Content of {path} does not match the expected predictions."


def test_inference_c_exists():
    path = "/home/user/inference.c"
    assert os.path.exists(path), f"Source file {path} is missing."
    assert os.path.isfile(path), f"Source path {path} is not a regular file."


def test_inference_bin_exists_and_executable():
    path = "/home/user/inference_bin"
    assert os.path.exists(path), f"Binary file {path} is missing."
    assert os.access(path, os.X_OK), f"Binary file {path} is not executable."
    assert os.path.isfile(path), f"Binary path {path} is not a regular file."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Binary file {path} is not a compiled ELF executable."


def _exercise(executable, rows):
    joined_path = "/home/user/joined_features.txt"
    predictions_path = "/home/user/predictions.log"

    with open(joined_path, "w") as f:
        for ident, feature_a, feature_b in rows:
            f.write(f"{ident} {feature_a}.0 {feature_b}.0\n")

    if os.path.lexists(predictions_path):
        os.remove(predictions_path)

    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{executable} failed with status {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(predictions_path), (
        f"{executable} did not create /home/user/predictions.log"
    )

    with open(predictions_path, "r") as f:
        actual = f.read().splitlines()

    expected = [
        f"{ident},{(1.5 * feature_a - 0.5 * feature_b + 0.1):.2f}"
        for ident, feature_a, feature_b in rows
    ]
    assert actual == expected, (
        f"{executable} did not implement the required model: "
        f"expected {expected}, got {actual}"
    )


def test_programs_execute_model_on_unseen_inputs():
    joined_path = "/home/user/joined_features.txt"
    predictions_path = "/home/user/predictions.log"

    with open(joined_path, "rb") as f:
        original_joined = f.read()
    original_predictions = None
    if os.path.exists(predictions_path):
        with open(predictions_path, "rb") as f:
            original_predictions = f.read()

    nonce = secrets.randbelow(800000) + 100000
    rows_for_submitted_binary = [
        (nonce + i, secrets.randbelow(41) - 20, secrets.randbelow(41) - 20)
        for i in range(6)
    ]
    rows_for_compiled_source = [
        (nonce + 100 + i, secrets.randbelow(61) - 30, secrets.randbelow(61) - 30)
        for i in range(6)
    ]

    rebuilt = "/tmp/verifier_inference_bin"
    try:
        _exercise("/home/user/inference_bin", rows_for_submitted_binary)

        compile_result = subprocess.run(
            ["gcc", "/home/user/inference.c", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert compile_result.returncode == 0, (
            "inference.c could not be compiled with gcc: " + compile_result.stderr
        )
        assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)
        _exercise(rebuilt, rows_for_compiled_source)
    finally:
        with open(joined_path, "wb") as f:
            f.write(original_joined)
        if original_predictions is None:
            if os.path.lexists(predictions_path):
                os.remove(predictions_path)
        else:
            with open(predictions_path, "wb") as f:
                f.write(original_predictions)
        if os.path.exists(rebuilt):
            os.remove(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
