#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import stat
import string
import subprocess

PROJECT = "/home/user/project"
AGENT_BINARY = os.path.join(PROJECT, "rle_encoder")
ORACLE_BINARY = "/app/legacy_encoder"
MAIN_CPP = os.path.join(PROJECT, "main.cpp")
ENCODER_CPP = os.path.join(PROJECT, "encoder.cpp")
ENCODER_H = os.path.join(PROJECT, "encoder.h")
UTILS_H = os.path.join(PROJECT, "utils.h")
MAKEFILE = os.path.join(PROJECT, "Makefile")


def run_checked(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def expected_output(value):
    if not value:
        return "\n"
    pieces = []
    count = 1
    for index in range(1, len(value)):
        if value[index] == value[index - 1]:
            count += 1
        else:
            pieces.append(value[index - 1] + str(count))
            count = 1
    pieces.append(value[-1] + str(count))
    return "".join(pieces) + "\n"


def generate_random_string(length):
    chars = string.ascii_letters + string.digits
    return "".join(random.choice(chars) for _ in range(length))


def test_repaired_project_builds_and_matches_legacy_behavior():
    required_files = [MAIN_CPP, ENCODER_CPP, ENCODER_H, UTILS_H, MAKEFILE]
    for path in required_files:
        assert os.path.isfile(path), f"Required project file is missing: {path}"

    assert os.path.isfile(ORACLE_BINARY), "The supplied legacy encoder is missing before verification."
    with open(ORACLE_BINARY, "rb") as handle:
        oracle_digest = hashlib.sha256(handle.read()).digest()

    # The rebuilt target must not be able to delegate its work to the legacy binary.
    os.unlink(ORACLE_BINARY)

    run_checked(["make", "clean"], cwd=PROJECT, timeout=20)
    if os.path.lexists(AGENT_BINARY):
        os.unlink(AGENT_BINARY)
    for name in os.listdir(PROJECT):
        if name.endswith(".o"):
            os.unlink(os.path.join(PROJECT, name))

    run_checked(["make", "rle_encoder"], cwd=PROJECT, timeout=30)

    assert os.path.exists(AGENT_BINARY), f"Executable {AGENT_BINARY} was not built by make."
    assert os.path.isfile(AGENT_BINARY), f"Path {AGENT_BINARY} is not a file."
    assert not os.path.islink(AGENT_BINARY), "rle_encoder must be a built executable, not a symlink."
    assert os.access(AGENT_BINARY, os.X_OK), f"Executable {AGENT_BINARY} is not executable."
    assert stat.S_ISREG(os.stat(AGENT_BINARY).st_mode), "rle_encoder is not a regular file."

    with open(AGENT_BINARY, "rb") as handle:
        agent_bytes = handle.read()
    assert agent_bytes.startswith(b"\x7fELF"), "rle_encoder is not a compiled ELF executable."
    assert hashlib.sha256(agent_bytes).digest() != oracle_digest, (
        "rle_encoder is byte-identical to the supplied legacy binary."
    )

    # Check that the complete benchmarking patch, rather than only its include, is present.
    with open(MAIN_CPP, "r", encoding="utf-8") as handle:
        main_content = handle.read()
    required_patch_fragments = [
        "#include <chrono>",
        "std::chrono::high_resolution_clock::now()",
        "std::chrono::duration<double>",
        "std::cerr",
        '"Time: "',
        '" s\\n"',
    ]
    for fragment in required_patch_fragments:
        assert fragment in main_content, f"Benchmarking patch fragment is missing: {fragment}"
    assert main_content.count("std::chrono::high_resolution_clock::now()") >= 2, (
        "The benchmarking patch must measure both start and end times."
    )

    random.seed(42)
    test_inputs = [""]
    for _ in range(500):
        test_inputs.append(generate_random_string(random.randint(1, 2000)))

    timing_pattern = re.compile(
        r"^Time: ([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?) s\n$"
    )
    for index, test_input in enumerate(test_inputs):
        try:
            result = subprocess.run(
                [AGENT_BINARY, test_input],
                capture_output=True,
                text=True,
                timeout=2,
            )
        except subprocess.TimeoutExpired:
            raise AssertionError(
                f"Execution timed out on iteration {index}, input length {len(test_input)}."
            )

        expected = expected_output(test_input)
        assert result.returncode == 0, (
            f"rle_encoder returned {result.returncode} on iteration {index}."
        )
        assert result.stdout == expected, (
            f"Output mismatch on iteration {index}.\n"
            f"Input length: {len(test_input)}\n"
            f"Input preview: {test_input[:50]}...\n"
            f"Expected output preview: {expected[:50]}...\n"
            f"Actual output preview: {result.stdout[:50]}..."
        )
        timing_match = timing_pattern.fullmatch(result.stderr)
        assert timing_match, (
            f"Benchmark timing output is missing or malformed on iteration {index}: "
            f"{result.stderr!r}"
        )
        assert float(timing_match.group(1)) >= 0.0
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
