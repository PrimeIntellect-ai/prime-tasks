#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest


def count_codepoints(s):
    # In Python 3, len() on a string counts Unicode codepoints
    return len(s)


def compute_expected_anomalies(input_path):
    with open(input_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    history = []
    last_accepted = None
    out = []

    for i, line in enumerate(lines):
        N = i + 1
        stripped = line.strip(" \t\r\n")
        if not stripped:
            continue
        if stripped == last_accepted:
            continue

        L = count_codepoints(stripped)

        if len(history) >= 3:
            avg = sum(history[-3:]) // 3
            if L > 2 * avg:
                out.append(f"Line {N}: {L} codepoints\n")

        history.append(L)
        last_accepted = stripped

    return out


def test_c_program_exists():
    src_path = "/home/user/detector.c"
    exe_path = "/home/user/detector"
    assert os.path.exists(src_path), f"The source file {src_path} is missing."
    assert os.path.exists(exe_path), f"The compiled executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."
    assert os.path.isfile(src_path), f"The source file {src_path} is not a regular file."
    assert os.path.isfile(exe_path), f"The executable {exe_path} is not a regular file."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF executable."


def test_anomalies_file_exists():
    anomalies_path = "/home/user/anomalies.txt"
    assert os.path.exists(anomalies_path), f"The file {anomalies_path} was not created."
    assert os.path.isfile(anomalies_path), f"{anomalies_path} is not a regular file."


def test_anomalies_content():
    input_path = "/home/user/input.txt"
    anomalies_path = "/home/user/anomalies.txt"

    assert os.path.exists(input_path), f"Input file {input_path} is missing, cannot compute expected anomalies."
    assert os.path.exists(anomalies_path), f"Anomalies file {anomalies_path} is missing."

    expected_lines = compute_expected_anomalies(input_path)

    with open(anomalies_path, "r", encoding="utf-8") as f:
        actual_lines = f.readlines()

    assert actual_lines == expected_lines, (
        f"The contents of {anomalies_path} do not match the expected output.\n"
        f"Expected:\n{''.join(expected_lines)}\n"
        f"Actual:\n{''.join(actual_lines)}"
    )


def run_case(executable, text):
    anomalies_path = "/home/user/anomalies.txt"
    fd, input_path = tempfile.mkstemp(prefix="detector_input_", suffix=".txt")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(text)

        expected_lines = compute_expected_anomalies(input_path)
        if os.path.lexists(anomalies_path):
            os.unlink(anomalies_path)

        result = subprocess.run(
            [executable, input_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
        assert result.returncode == 0, (
            f"{executable} exited with status {result.returncode}.\n"
            f"stdout: {result.stdout.decode('utf-8', errors='replace')}\n"
            f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
        )
        assert os.path.exists(anomalies_path), (
            f"{executable} did not create {anomalies_path}."
        )
        assert os.path.isfile(anomalies_path), (
            f"{anomalies_path} is not a regular file after running {executable}."
        )
        with open(anomalies_path, "r", encoding="utf-8") as f:
            actual_lines = f.readlines()
        assert actual_lines == expected_lines, (
            f"Incorrect output from {executable} for generated input.\n"
            f"Expected:\n{''.join(expected_lines)}\n"
            f"Actual:\n{''.join(actual_lines)}"
        )
    finally:
        if os.path.exists(input_path):
            os.unlink(input_path)


def test_detector_on_additional_inputs():
    deterministic_cases = [
        (
            " a \n"
            "\ta\t\n"
            "bb\n"
            "   \n"
            "ccc\n"
            "ddddddd\n"
            " ddddddd \n"
            "éé\n"
            "👩🏽‍🚀👨🏽‍🚀\n"
        ),
        (
            "A\n"
            "B\n"
            "CCC\n"
            "XYZ\n"
            "\t\n"
            "XYZ\n"
            "界界界界界界界界界界界界\n"
        ),
        (
            "same\n"
            " same \n"
            "\n"
            "tiny\n"
            "small\n"
        ),
    ]

    a = 1 + secrets.randbelow(7)
    b = 1 + secrets.randbelow(7)
    c = 1 + secrets.randbelow(7)
    long_len = 2 * ((a + b + c) // 3) + 1 + secrets.randbelow(6)
    generated = (
        " " + ("A" + "α" * (a - 1)) + " \n"
        "\t" + ("A" + "α" * (a - 1)) + "\t\n"
        "   \n"
        + ("B" + "界" * (b - 1)) + "\n"
        + ("C" + "é" * (c - 1)) + "\n"
        + ("D" + "🚀" * (long_len - 1)) + "\n"
        "tail\n"
    )
    cases = deterministic_cases + [generated]

    rebuilt = tempfile.NamedTemporaryFile(prefix="rebuilt_detector_", delete=False)
    rebuilt_path = rebuilt.name
    rebuilt.close()
    try:
        compile_result = subprocess.run(
            ["gcc", "/home/user/detector.c", "-o", rebuilt_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert compile_result.returncode == 0, (
            "The submitted detector.c did not compile with gcc.\n"
            + compile_result.stderr.decode("utf-8", errors="replace")
        )

        for executable in ("/home/user/detector", rebuilt_path):
            for case in cases:
                run_case(executable, case)
    finally:
        if os.path.exists(rebuilt_path):
            os.unlink(rebuilt_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
