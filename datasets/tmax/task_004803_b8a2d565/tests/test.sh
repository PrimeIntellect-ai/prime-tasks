#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/log_parser_fixed"
SOURCE = "/home/user/log_parser.c"
ORIGINAL_LOGS = "/home/user/logs/"
ORIGINAL_OUTPUT = "/home/user/output_metrics.txt"
REPORT = "/home/user/trace_report.txt"


def run_parser(executable, log_dir, output_path):
    result = subprocess.run(
        [executable, log_dir + "/", output_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(output_path), f"Parser did not create {output_path}."
    with open(output_path, "r") as f:
        content = f.read()
    assert re.fullmatch(r"[+-]?\d+\n?", content), (
        f"Output must contain only one integer, got {content!r}."
    )
    return int(content.strip())


def make_dynamic_logs(base):
    log_dir = os.path.join(base, "logs_" + secrets.token_hex(5))
    os.mkdir(log_dir)

    values = [secrets.randbelow(80) + 10 for _ in range(2)]
    boundary_value = secrets.randbelow(900) + 100
    extra_value = secrets.randbelow(900) + 100

    metric = f"metric={boundary_value}"
    exact_64 = "X" * (64 - len(metric)) + metric
    assert len(exact_64) == 64

    metric_65 = f"metric={extra_value}"
    exact_65 = metric_65 + "Y" * (65 - len(metric_65))
    assert len(exact_65) == 65

    names = [secrets.token_hex(6) + ".log", secrets.token_hex(6) + ".log"]
    with open(os.path.join(log_dir, names[0]), "w") as f:
        f.write(f"metric={values[0]}\n")
        f.write(exact_64 + "\n")
    with open(os.path.join(log_dir, names[1]), "w") as f:
        f.write(exact_65 + "\n")
        f.write(f"prefix-metric={values[1]}\n")

    # Files that are not logs must not contribute to the total.
    with open(os.path.join(log_dir, secrets.token_hex(5) + ".txt"), "w") as f:
        f.write("metric=999999\n")

    return log_dir, sum(values) + boundary_value + extra_value


def test_fixed_executable_exists():
    executable_path = EXECUTABLE
    assert os.path.isfile(executable_path), f"The fixed executable {executable_path} is missing."
    assert os.access(executable_path, os.X_OK), f"The file {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_parser_fixed must be a compiled ELF executable."


def test_output_metrics_file():
    result = subprocess.run(
        [EXECUTABLE, ORIGINAL_LOGS, ORIGINAL_OUTPUT],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Fixed parser failed on the supplied logs: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )

    output_path = ORIGINAL_OUTPUT
    assert os.path.isfile(output_path), f"The output file {output_path} is missing."
    with open(output_path, "r") as f:
        content = f.read().strip()
    assert content == "250", f"Expected output metrics to be '250', but got '{content}'."


def test_trace_report_file():
    report_path = REPORT
    assert os.path.isfile(report_path), f"The diagnostic report {report_path} is missing."
    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"The report {report_path} must contain at least two lines."
    line1 = lines[0]
    line2 = lines[1]
    assert "app_3.log" in line1, f"Expected the first line to indicate 'app_3.log', but got '{line1}'."
    assert "read" in line2.lower(), f"Expected the second line to indicate the 'read' system call, but got '{line2}'."

    with open(report_path, "r") as f:
        exact_lines = f.read().splitlines()
    assert exact_lines == ["app_3.log", "read"], (
        "trace_report.txt must contain exactly the two requested lines."
    )


def test_fixed_executable_on_dynamic_boundary_inputs():
    with tempfile.TemporaryDirectory() as base:
        log_dir, expected = make_dynamic_logs(base)
        output = os.path.join(base, "artifact_output.txt")
        assert run_parser(EXECUTABLE, log_dir, output) == expected


def test_source_is_fixed_and_rebuilds_cleanly():
    assert os.path.isfile(SOURCE), f"The fixed source {SOURCE} is missing."
    with tempfile.TemporaryDirectory() as base:
        rebuilt = os.path.join(base, "rebuilt_parser")
        sanitized = os.path.join(base, "sanitized_parser")

        compile_result = subprocess.run(
            ["gcc", "-g", "-O0", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            f"Fixed source does not compile: {compile_result.stderr}"
        )

        asan_result = subprocess.run(
            ["gcc", "-g", "-O0", "-fsanitize=address", "-fno-omit-frame-pointer",
             SOURCE, "-o", sanitized],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert asan_result.returncode == 0, (
            f"Could not build the fixed source with AddressSanitizer: {asan_result.stderr}"
        )

        log_dir, expected = make_dynamic_logs(base)
        assert run_parser(rebuilt, log_dir, os.path.join(base, "rebuilt_output.txt")) == expected

        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        sanitized_output = os.path.join(base, "sanitized_output.txt")
        result = subprocess.run(
            [sanitized, log_dir + "/", sanitized_output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            env=env,
        )
        assert result.returncode == 0, (
            "The rebuilt source still performs an out-of-bounds memory access. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        with open(sanitized_output, "r") as f:
            content = f.read()
        assert re.fullmatch(r"[+-]?\d+\n?", content)
        assert int(content.strip()) == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
