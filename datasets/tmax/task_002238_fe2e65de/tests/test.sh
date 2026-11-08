#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile


def test_fixed_output_exists():
    """Test that the fixed output file exists."""
    output_file = "/home/user/fixed_output.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing. Did you redirect the output?"


def test_fixed_output_content():
    """Test that the fixed output file contains the correct calculated values."""
    output_file = "/home/user/fixed_output.txt"
    with open(output_file, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Total Time: 100.875",
        "Uptime: 90.500",
        "Percentage: 89.714994"
    ]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert len(actual_lines) == 3, f"Expected 3 lines of output, got {len(actual_lines)}."
    assert actual_lines[0] == expected_lines[0], f"Expected '{expected_lines[0]}', got '{actual_lines[0]}'."
    assert actual_lines[1] == expected_lines[1], f"Expected '{expected_lines[1]}', got '{actual_lines[1]}'."
    assert actual_lines[2] == expected_lines[2], f"Expected '{expected_lines[2]}', got '{actual_lines[2]}'."


def test_monitor_c_modifications():
    """Test that monitor.c was modified to fix the bugs."""
    source_file = "/home/user/monitor.c"
    assert os.path.isfile(source_file), f"Source file {source_file} is missing."

    with open(source_file, "r") as f:
        content = f.read()

    assert "double" in content, "The source code does not seem to use 'double' precision, which is necessary to fix the numerical instability."


def _expected_output(rows):
    times = [float(timestamp) for timestamp, _ in rows]
    total_time = 0.0
    total_uptime = 0.0
    for index in range(1, len(rows)):
        duration = times[index] - times[index - 1]
        total_time += duration
        if rows[index - 1][1] == 1:
            total_uptime += duration
    percentage = (total_uptime / total_time) * 100.0
    return (
        f"Total Time: {total_time:.3f}\n"
        f"Uptime: {total_uptime:.3f}\n"
        f"Percentage: {percentage:.6f}"
    )


def _write_log(path, rows):
    with open(path, "w") as f:
        for timestamp, status in rows:
            f.write(f"{timestamp} {status}\n")
        f.write("END\n")


def _format_milliseconds(value):
    return f"{value // 1000}.{value % 1000:03d}"


def test_compiled_program_terminates_and_calculates_dynamic_logs():
    """Compile and execute the submitted source against verifier-generated logs."""
    source_file = "/home/user/monitor.c"
    log_file = "/home/user/uptime_logs.txt"
    output_file = "/home/user/fixed_output.txt"

    with open(log_file, "rb") as f:
        original_log = f.read()
    with open(output_file, "r") as f:
        submitted_output = f.read().strip()

    with tempfile.TemporaryDirectory() as temp_dir:
        executable = os.path.join(temp_dir, "monitor")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", source_file, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert compile_result.returncode == 0, f"monitor.c does not compile:\n{compile_result.stderr}"

        rng = random.SystemRandom()
        statuses = [1, 0, 1, 1, 0, 1, 0]

        try:
            for _ in range(3):
                current_ms = rng.randrange(1_550_000_000_000, 1_850_000_000_000)
                rows = [(_format_milliseconds(current_ms), statuses[0])]
                for status in statuses[1:]:
                    current_ms += rng.randrange(101, 30001)
                    rows.append((_format_milliseconds(current_ms), status))

                _write_log(log_file, rows)
                expected = _expected_output(rows)
                try:
                    result = subprocess.run(
                        [executable],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=3,
                    )
                except subprocess.TimeoutExpired:
                    raise AssertionError("The compiled monitoring program did not terminate.")

                assert result.returncode == 0, (
                    f"The compiled monitoring program exited with {result.returncode}:\n{result.stderr}"
                )
                assert result.stdout.strip() == expected, (
                    "The compiled program produced an incorrect result for a verifier-generated log.\n"
                    f"Expected:\n{expected}\nGot:\n{result.stdout.strip()}"
                )
        finally:
            with open(log_file, "wb") as f:
                f.write(original_log)

        result = subprocess.run(
            [executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3,
        )
        assert result.returncode == 0, f"Program failed on the original log: {result.stderr}"
        assert result.stdout.strip() == submitted_output, (
            "fixed_output.txt does not match the compiled fixed program's output on the original log."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
