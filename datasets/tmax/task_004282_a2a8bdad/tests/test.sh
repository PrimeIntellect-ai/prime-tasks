#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile


def test_crash_line_extracted():
    """Verify that the crash line was correctly extracted from the core dump."""
    crash_line_path = "/home/user/crash_line.txt"
    assert os.path.isfile(crash_line_path), f"File {crash_line_path} does not exist."

    with open(crash_line_path, "r") as f:
        content = f.read()

    expected_line = "2023-01-01 10:10:00|ERROR"
    assert content == expected_line, f"Expected crash line to be exactly '{expected_line}', but got '{content}'."


def test_makefile_fixed():
    """Verify that the legacy headers include path was removed from the Makefile."""
    makefile_path = "/home/user/log_processor/Makefile"
    assert os.path.isfile(makefile_path), f"File {makefile_path} does not exist."

    with open(makefile_path, "r") as f:
        content = f.read()

    assert "-I/home/user/legacy_headers" not in content, "Makefile still contains the conflicting legacy headers include path (-I/home/user/legacy_headers)."


def test_processor_c_null_check():
    """Verify that processor.c includes a null-check for the message variable."""
    source_path = "/home/user/log_processor/processor.c"
    assert os.path.isfile(source_path), f"File {source_path} does not exist."

    with open(source_path, "r") as f:
        content = f.read()

    null_check_pattern = r'(!message|message\s*==\s*NULL|message\s*!=\s*NULL|message\s*&&|if\s*\(\s*message\s*\))'
    assert re.search(null_check_pattern, content), "Could not find a null-check for 'message' in processor.c before calling strlen."


def exercise_processor(exe_path):
    """Exercise valid and malformed records using verifier-generated values."""
    nonce = secrets.token_hex(10)
    long_timestamp = f"dynamic-{nonce}"
    long_message = "M" * 121
    malformed_timestamp = f"missing-{secrets.token_hex(8)}"

    lines = [
        f"{malformed_timestamp}|ERROR",
        f"single-{secrets.token_hex(8)}",
        f"empty-message-{secrets.token_hex(8)}|WARN|",
        f"{long_timestamp}|INFO|{long_message}",
        f"short-{secrets.token_hex(8)}|INFO|ok",
    ]
    expected_stdout = f"Long message at {long_timestamp}\n"

    with tempfile.NamedTemporaryFile("w", delete=False) as log_file:
        log_file.write("\n".join(lines) + "\n")
        log_path = log_file.name

    try:
        result = subprocess.run(
            [exe_path, log_path], capture_output=True, text=True, timeout=10
        )
    finally:
        os.unlink(log_path)

    assert result.returncode == 0, (
        f"log_processor failed on generated malformed records with exit code "
        f"{result.returncode}. Stderr: {result.stderr}"
    )
    assert result.stdout == expected_stdout, (
        "The processor did not safely ignore malformed/short records or did not "
        f"process the valid long-message record correctly. Expected stdout "
        f"{expected_stdout!r}, got {result.stdout!r}."
    )


def test_fixed_source_behavior():
    """Compile processor.c directly and prove the source safely parses generated input."""
    source_path = "/home/user/log_processor/processor.c"
    with tempfile.TemporaryDirectory() as temp_dir:
        exe_path = os.path.join(temp_dir, "processor_from_source")
        build = subprocess.run(
            ["gcc", "-std=c11", "-g", "-o", exe_path, source_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, (
            f"processor.c could not be compiled with the system headers: {build.stderr}"
        )
        exercise_processor(exe_path)


def test_executable_runs_flawlessly():
    """Rebuild with make and verify the resulting executable on fixed and generated logs."""
    project_dir = "/home/user/log_processor"
    exe_path = os.path.join(project_dir, "log_processor")
    log_path = "/home/user/data/input.log"

    if os.path.lexists(exe_path):
        os.unlink(exe_path)

    build = subprocess.run(
        ["make", "-B"], cwd=project_dir, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"make failed: {build.stdout}\n{build.stderr}"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist. Did you recompile?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    with open(exe_path, "rb") as executable_file:
        assert executable_file.read(4) == b"\x7fELF", "log_processor is not a compiled ELF executable."

    result = subprocess.run(
        [exe_path, log_path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"log_processor failed with exit code {result.returncode}. Stderr: {result.stderr}"

    exercise_processor(exe_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
