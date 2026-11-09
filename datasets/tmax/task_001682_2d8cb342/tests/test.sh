#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest


def run_processor(binary_path, log_path, timeout=5):
    try:
        return subprocess.run(
            [binary_path, log_path],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{binary_path} timed out while processing {log_path}.")


def test_solution_file():
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), f"Solution file {solution_path} does not exist."

    with open(solution_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {solution_path}, found {len(lines)}."
    assert lines[0] == "Crashing Line: 6834", f"First line is incorrect. Expected 'Crashing Line: 6834', got '{lines[0]}'"
    assert lines[1] == "Token: parsed_9999_valid_lines", f"Second line is incorrect. Expected 'Token: parsed_9999_valid_lines', got '{lines[1]}'"


def test_binary_fixed():
    binary_path = "/home/user/log_processor"
    log_path = "/home/user/app_logs.txt"

    assert os.path.isfile(binary_path), f"Binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_processor must be a compiled ELF executable, not a script."

    result = run_processor(binary_path, log_path)
    assert result.returncode == 0, f"The log_processor binary crashed or returned non-zero exit code: {result.returncode}. Stderr: {result.stderr}"

    output = result.stdout.strip()
    assert "SUCCESS_TOKEN: parsed_9999_valid_lines" in output, f"The binary did not print the expected success token. Output: {output}"


def test_repaired_source_and_unseen_malformed_inputs():
    source_path = "/home/user/log_processor.c"
    installed_binary = "/home/user/log_processor"
    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."

    with tempfile.TemporaryDirectory() as td:
        rebuilt_binary = os.path.join(td, "log_processor_rebuilt")
        try:
            compile_result = subprocess.run(
                ["gcc", source_path, "-o", rebuilt_binary],
                capture_output=True,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Recompiling /home/user/log_processor.c timed out.")

        assert compile_result.returncode == 0, (
            "The repaired source does not compile with gcc. "
            f"Stderr: {compile_result.stderr}"
        )
        with open(rebuilt_binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Recompiled source did not produce an ELF executable."

        rng = random.SystemRandom()
        for case_number in range(5):
            valid_count = rng.randint(3, 30)
            malformed_count = rng.randint(2, 12)
            nonce = os.urandom(8).hex()

            lines = [
                f"2026-09-11T12:34:{i % 60:02d}Z|INFO|message_{nonce}_{case_number}_{i}\n"
                for i in range(valid_count)
            ]
            malformed_templates = [
                f"2026-09-11T12:35:00Z|ERROR_{nonce}\n",
                f"undelimited_corruption_{nonce}\n",
                f"2026-09-11T12:36:00Z|WARN\n",
                "|||\n",
            ]
            lines.extend(
                malformed_templates[i % len(malformed_templates)]
                for i in range(malformed_count)
            )
            rng.shuffle(lines)

            fixture = os.path.join(td, f"unseen_{nonce}_{case_number}.log")
            with open(fixture, "w") as f:
                f.writelines(lines)

            expected = f"SUCCESS_TOKEN: parsed_{valid_count}_valid_lines"
            for executable in (installed_binary, rebuilt_binary):
                result = run_processor(executable, fixture)
                assert result.returncode == 0, (
                    f"{executable} crashed or returned {result.returncode} on unseen malformed input. "
                    f"Stderr: {result.stderr}"
                )
                assert result.stdout.strip() == expected, (
                    f"{executable} did not safely skip malformed lines. "
                    f"Expected '{expected}', got '{result.stdout.strip()}'."
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
