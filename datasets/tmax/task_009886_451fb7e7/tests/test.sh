#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

WORKSPACE = "/home/user/pr_review"
EXECUTABLE = os.path.join(WORKSPACE, "log_parser")


def test_makefile_builds_correctly():
    # Make sure we can clean and build using the provided Makefile.
    clean_result = subprocess.run(["make", "clean"], cwd=WORKSPACE, capture_output=True)
    assert clean_result.returncode == 0, f"'make clean' failed: {clean_result.stderr.decode()}"

    build_result = subprocess.run(["make"], cwd=WORKSPACE, capture_output=True)
    assert build_result.returncode == 0, (
        f"'make' failed to build log_parser. Error:\n{build_result.stderr.decode()}"
    )

    assert os.path.isfile(EXECUTABLE), "log_parser executable was not created by 'make'."
    assert os.access(EXECUTABLE, os.X_OK), "log_parser is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_parser is not a compiled ELF executable."


def test_output_files_exist():
    py_out = os.path.join(WORKSPACE, "py_out.txt")
    cpp_out = os.path.join(WORKSPACE, "cpp_out.txt")
    valgrind_out = os.path.join(WORKSPACE, "valgrind_report.txt")

    assert os.path.isfile(py_out), f"{py_out} is missing. Did you run the Python script?"
    assert os.path.isfile(cpp_out), f"{cpp_out} is missing. Did you run the C++ program?"
    assert os.path.isfile(valgrind_out), f"{valgrind_out} is missing. Did you run Valgrind?"


def test_execution_correctness():
    py_out = os.path.join(WORKSPACE, "py_out.txt")
    cpp_out = os.path.join(WORKSPACE, "cpp_out.txt")

    with open(py_out, "r") as f:
        py_content = f.read().strip()

    with open(cpp_out, "r") as f:
        cpp_content = f.read().strip()

    assert py_content == cpp_content, (
        "The output of the C++ program does not exactly match the Python program."
    )

    expected_lines = [
        "ERR05: 1",
        "ERR12: 2",
        "ERR99: 1",
    ]
    for line in expected_lines:
        assert line in cpp_content, f"Expected output line '{line}' missing from cpp_out.txt."


def make_runtime_case():
    # Build an unpredictable input and derive its answer independently of submitted files.
    counts = {}
    lines = []

    valid_codes = ["ERR" + f"{secrets.randbelow(100):02d}" for _ in range(18)]
    for code in valid_codes:
        repetitions = 1 + secrets.randbelow(4)
        for _ in range(repetitions):
            lines.append(f"2026-09-12 {code} runtime message")
            counts[code] = counts.get(code, 0) + 1

    invalid_codes = [
        "ERR", "ERR0", "ERR000", "ERRAA", "ER123", "err12", "INFO1",
        "XERR12", "ERR1X", "ERR-1", "ERR 12",
    ]
    alphabet = string.ascii_uppercase + string.digits
    for _ in range(30):
        invalid_codes.append("BAD" + "".join(secrets.choice(alphabet) for _ in range(2)))
    for code in invalid_codes:
        lines.append(f"2026-09-12 {code} ignored message")

    lines.extend(["", "single-token", "2026-09-12"])
    secrets.SystemRandom().shuffle(lines)
    expected = "".join(f"{code}: {counts[code]}\n" for code in sorted(counts))
    return "\n".join(lines) + "\n", expected


def test_built_executable_on_runtime_generated_input(tmp_path):
    data, expected = make_runtime_case()
    input_path = tmp_path / "runtime_logs.txt"
    input_path.write_text(data)

    result = subprocess.run(
        [EXECUTABLE, str(input_path)],
        cwd=WORKSPACE,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"log_parser failed on generated input: {result.stderr.decode(errors='replace')}"
    )
    assert result.stdout.decode() == expected, (
        "log_parser produced incorrect output on runtime-generated log data."
    )


def test_valgrind_memory_leak_resolved(tmp_path):
    valgrind_out = os.path.join(WORKSPACE, "valgrind_report.txt")

    with open(valgrind_out, "r") as f:
        valgrind_content = f.read()

    # Preserve the required assertion on the report produced by the agent.
    assert "definitely lost: 0 bytes in 0 blocks" in valgrind_content, (
        "Valgrind report does not indicate 'definitely lost: 0 bytes in 0 blocks'. "
        "The memory leak may not be fully resolved."
    )

    # Independently profile the executable instead of trusting the saved report.
    data, expected = make_runtime_case()
    input_path = tmp_path / "valgrind_runtime_logs.txt"
    input_path.write_text(data)
    result = subprocess.run(
        [
            "valgrind",
            "--leak-check=full",
            "--show-leak-kinds=definite",
            "--errors-for-leak-kinds=definite",
            "--error-exitcode=97",
            EXECUTABLE,
            str(input_path),
        ],
        cwd=WORKSPACE,
        capture_output=True,
        timeout=30,
    )
    report = result.stderr.decode(errors="replace")
    assert result.returncode == 0, f"Valgrind detected an error or leak:\n{report}"
    assert result.stdout.decode() == expected, (
        "The executable produced incorrect output while running under Valgrind."
    )
    assert "definitely lost: 0 bytes in 0 blocks" in report, (
        "A fresh Valgrind run did not report exactly 0 definitely lost bytes."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
