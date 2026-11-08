#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import struct
import subprocess
import time


def expected_metrics(bin_file):
    with open(bin_file, "rb") as f:
        data = f.read()

    assert len(data) % 4 == 0, "Binary data length must be divisible by four."
    n = len(data) // 4
    assert n > 0, "Binary data file is empty."

    floats = struct.unpack(f"<{n}f", data)
    total = math.fsum(floats)
    mean = total / n
    var_sum = math.fsum((x - mean) ** 2 for x in floats)
    variance = var_sum / n
    return f"{mean:.4f}", f"{variance:.4f}"


def parse_metrics(content):
    lines = [line.strip() for line in content.split('\n') if line.strip()]
    assert len(lines) >= 2, "Output must contain at least two lines for Mean and Variance."
    assert lines[0].startswith("Mean:"), "First line must start with 'Mean:'"
    assert lines[1].startswith("Variance:"), "Second line must start with 'Variance:'"
    return lines[0].split(":", 1)[1].strip(), lines[1].split(":", 1)[1].strip()


def test_solution_file_exists_and_correct():
    solution_file = "/home/user/solution.txt"
    bin_file = "/home/user/uptime_stats/data/latencies.bin"

    assert os.path.isfile(bin_file), f"Data file {bin_file} is missing."
    assert os.path.isfile(solution_file), f"Solution file {solution_file} is missing."

    expected_mean_str, expected_variance_str = expected_metrics(bin_file)

    with open(solution_file, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.split('\n') if line.strip()]
    assert len(lines) >= 2, "solution.txt must contain at least two lines for Mean and Variance."

    mean_line = lines[0]
    var_line = lines[1]

    assert mean_line.startswith("Mean:"), "First line must start with 'Mean:'"
    assert var_line.startswith("Variance:"), "Second line must start with 'Variance:'"

    actual_mean_str = mean_line.split(":", 1)[1].strip()
    actual_variance_str = var_line.split(":", 1)[1].strip()

    assert actual_mean_str == expected_mean_str, (
        f"Mean is incorrect. Expected {expected_mean_str}, got {actual_mean_str}. "
        "Check precision loss or missing data points."
    )
    assert actual_variance_str == expected_variance_str, (
        f"Variance is incorrect. Expected {expected_variance_str}, got {actual_variance_str}. "
        "Check for numerical instability or missing data points."
    )


def run_program(executable, cwd, monitor_threads=False, timeout=30):
    proc = subprocess.Popen(
        [executable], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    max_tasks = 1
    deadline = time.monotonic() + timeout

    while proc.poll() is None:
        if time.monotonic() > deadline:
            proc.kill()
            stdout, stderr = proc.communicate()
            raise AssertionError(f"Rust program timed out. stdout={stdout!r}, stderr={stderr!r}")
        if monitor_threads:
            try:
                max_tasks = max(max_tasks, len(os.listdir(f"/proc/{proc.pid}/task")))
            except FileNotFoundError:
                pass
        time.sleep(0.0005)

    stdout, stderr = proc.communicate()
    assert proc.returncode == 0, (
        f"Rust program exited with status {proc.returncode}. "
        f"stdout={stdout!r}, stderr={stderr!r}"
    )
    if monitor_threads:
        assert max_tasks >= 2, (
            "The running Rust implementation was never observed using more than one thread."
        )
    return stdout


def assert_program_output(stdout, expected_mean, expected_variance):
    actual_mean, actual_variance = parse_metrics(stdout)
    assert actual_mean == expected_mean, (
        f"Program mean is incorrect. Expected {expected_mean}, got {actual_mean}."
    )
    assert actual_variance == expected_variance, (
        f"Program variance is incorrect. Expected {expected_variance}, got {actual_variance}."
    )


def test_rust_program_builds_runs_concurrently_and_handles_unseen_data():
    project = "/home/user/uptime_stats"
    source = os.path.join(project, "src/main.rs")
    bin_file = os.path.join(project, "data/latencies.bin")
    backup = "/tmp/original_latencies.bin"

    assert os.path.isfile(source), "src/main.rs is missing."
    build = subprocess.run(
        ["cargo", "build"], cwd=project, text=True, capture_output=True, timeout=120
    )
    assert build.returncode == 0, (
        f"cargo build failed. stdout={build.stdout!r}, stderr={build.stderr!r}"
    )

    executable = os.path.join(project, "target/debug/uptime_stats")
    assert os.path.isfile(executable), "cargo did not produce the uptime_stats executable."
    assert os.access(executable, os.X_OK), "The built uptime_stats artifact is not executable."

    expected_mean, expected_variance = expected_metrics(bin_file)
    stdout = run_program(executable, project, monitor_threads=True)
    assert_program_output(stdout, expected_mean, expected_variance)

    shutil.copy2(bin_file, backup)
    try:
        # Runtime-generated, non-divisible-by-four input with a large offset and
        # small spread catches dropped remainders, f32 accumulation, and unstable variance.
        state = 0x6A09E667F3BCC909
        values = []
        for i in range(200003):
            state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
            offset = ((state >> 32) % 17 - 8) * 0.0625
            if i % 997 == 0:
                offset += 0.1875
            values.append(1_000_000.0 + offset)

        replacement = "/tmp/generated_latencies.bin"
        with open(replacement, "wb") as f:
            for value in values:
                f.write(struct.pack("<f", value))
        os.replace(replacement, bin_file)

        expected_mean, expected_variance = expected_metrics(bin_file)
        stdout = run_program(executable, project)
        assert_program_output(stdout, expected_mean, expected_variance)
    finally:
        if os.path.exists(backup):
            os.replace(backup, bin_file)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
