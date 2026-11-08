#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess


def expected_stats(data):
    state = 42

    def my_rand():
        nonlocal state
        state = (state * 1103515245 + 12345) & 0xFFFFFFFF
        return (state // 65536) % 32768

    means = []
    for _ in range(10000):
        current_sum = 0.0
        for _ in range(100):
            current_sum += data[my_rand() % 100]
        means.append(current_sum / 100.0)

    overall_mean = sum(means) / 10000.0
    stddev = math.sqrt(sum((m - overall_mean) ** 2 for m in means) / 10000.0)
    means.sort()
    return (
        f"Mean: {overall_mean:.4f}\n"
        f"StdDev: {stddev:.4f}\n"
        f"CI_Lower: {means[250]:.4f}\n"
        f"CI_Upper: {means[9750]:.4f}\n"
    )


def parse_metrics(text):
    lines = text.strip().split("\n")
    assert len(lines) == 100, f"Expected exactly 100 metric lines, found {len(lines)}."
    try:
        return [float(line) for line in lines]
    except ValueError as exc:
        raise AssertionError(f"Workload produced a non-floating-point line: {exc}")


def test_workload_compiled_and_runs():
    executable_path = "/home/user/workload"
    assert os.path.exists(executable_path), f"Executable {executable_path} is missing."
    assert os.path.isfile(executable_path), f"{executable_path} is not a file."
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable_path} is not a compiled ELF executable."

    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = "4"
    result = subprocess.run(
        [executable_path], env=env, text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, f"Workload failed: {result.stderr}"
    values = parse_metrics(result.stdout)
    for i, value in enumerate(values):
        expected = 100.0 + 10.0 * math.sin(i) + (i % 3)
        assert abs(value - expected) < 1e-3, (
            f"Executed workload line {i + 1} expected ~{expected:.4f}, got {value}"
        )


def test_metrics_txt():
    metrics_path = "/home/user/metrics.txt"
    assert os.path.exists(metrics_path), f"File {metrics_path} is missing."
    with open(metrics_path, "r") as f:
        lines = f.read().strip().split("\n")
    assert len(lines) == 100, f"Expected exactly 100 lines in metrics.txt, found {len(lines)}."
    for i, line in enumerate(lines):
        expected_val = 100.0 + 10.0 * math.sin(i) + (i % 3)
        try:
            val = float(line)
        except ValueError:
            assert False, f"Line {i + 1} in metrics.txt is not a valid float: {line}"
        assert abs(val - expected_val) < 1e-3, (
            f"Line {i + 1} expected ~{expected_val:.4f}, got {val}"
        )


def test_analyze_c_exists():
    analyze_path = "/home/user/analyze.c"
    assert os.path.exists(analyze_path), f"File {analyze_path} is missing."
    assert os.path.isfile(analyze_path), f"{analyze_path} is not a file."


def test_stats_log():
    stats_path = "/home/user/stats.log"
    assert os.path.exists(stats_path), f"File {stats_path} is missing."
    data = [100.0 + 10.0 * math.sin(i) + (i % 3) for i in range(100)]
    expected_output = expected_stats(data)
    with open(stats_path, "r") as f:
        actual_output = f.read()
    assert actual_output.strip() == expected_output.strip(), (
        f"Contents of {stats_path} do not match the expected output.\n"
        f"Expected:\n{expected_output}\nActual:\n{actual_output}"
    )


def test_analyzer_compiles_and_processes_independent_inputs():
    source = "/home/user/analyze.c"
    analyzer = "/tmp/analyze_verified"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", source, "-lm", "-o", analyzer],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"analyze.c did not compile successfully:\n{compile_result.stderr}"
    )
    with open(analyzer, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled analyzer is not an ELF executable."

    metrics_path = "/home/user/metrics.txt"
    stats_path = "/home/user/stats.log"
    with open(metrics_path, "rb") as f:
        saved_metrics = f.read()
    with open(stats_path, "rb") as f:
        saved_stats = f.read()

    try:
        for case in range(2):
            values = [
                (secrets.randbelow(400001) - 100000 + case * (i + 1)) / 1000.0
                for i in range(100)
            ]
            with open(metrics_path, "w") as f:
                for value in values:
                    f.write(f"{value:.6f}\n")
            if os.path.exists(stats_path):
                os.unlink(stats_path)

            result = subprocess.run(
                [analyzer], cwd="/home/user", text=True, capture_output=True, timeout=30
            )
            assert result.returncode == 0, (
                f"Analyzer failed on independent input {case + 1}: {result.stderr}"
            )
            assert os.path.isfile(stats_path), "Analyzer did not create /home/user/stats.log."
            with open(stats_path, "r") as f:
                actual = f.read()
            expected = expected_stats(values)
            assert actual.strip() == expected.strip(), (
                f"Analyzer produced incorrect output for independent input {case + 1}.\n"
                f"Expected:\n{expected}\nActual:\n{actual}"
            )
    finally:
        with open(metrics_path, "wb") as f:
            f.write(saved_metrics)
        with open(stats_path, "wb") as f:
            f.write(saved_stats)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
