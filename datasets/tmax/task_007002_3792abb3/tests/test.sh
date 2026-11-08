#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess


def test_c_source_exists():
    assert os.path.isfile("/home/user/simulate_latency.c"), "C simulator source code is missing."


def test_pipeline_script_exists():
    assert os.path.isfile("/home/user/pipeline.sh"), "Bash pipeline script is missing."


def test_data_files_exist():
    assert os.path.isfile("/home/user/data_A.txt"), "data_A.txt is missing."
    assert os.path.isfile("/home/user/data_B.txt"), "data_B.txt is missing."


def test_venv_exists():
    assert os.path.isdir("/home/user/venv"), "Python virtual environment directory is missing."
    assert os.path.isfile("/home/user/venv/bin/python"), "Python executable not found in venv."


def test_analyze_script_exists():
    assert os.path.isfile("/home/user/analyze.py"), "Python analysis script is missing."


def test_stats_json_exists():
    assert os.path.isfile("/home/user/stats.json"), "stats.json is missing."


def test_stats_json_content():
    # Verify the venv has scipy installed and compute ground truth
    script = """
import sys
import json
try:
    from scipy import stats
except ImportError:
    print("SCIPY_MISSING")
    sys.exit(0)

def my_rand(state):
    state = (state * 1103515245 + 12345) & 0x7fffffff
    return state

def run_mode(mode, seed, n):
    state = seed
    total = 0.0
    for _ in range(n):
        state = my_rand(state)
        if mode == 'A':
            total += (state % 100) / 10.0
        else:
            total += (state % 105) / 10.0
    return total

mode_a = [run_mode('A', s, 1000) for s in range(1, 51)]
mode_b = [run_mode('B', s, 1000) for s in range(1, 51)]

res = stats.ttest_ind(mode_a, mode_b, equal_var=False)
print(json.dumps({
    "t_statistic": round(float(res.statistic), 4),
    "p_value": round(float(res.pvalue), 4)
}))
"""
    result = subprocess.run(["/home/user/venv/bin/python", "-c", script], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run ground truth script using the student's venv."

    stdout = result.stdout.strip()
    assert stdout != "SCIPY_MISSING", "scipy is not installed in the virtual environment."

    try:
        expected_data = json.loads(stdout)
    except json.JSONDecodeError:
        assert False, f"Failed to parse ground truth JSON. Output was: {stdout}"

    try:
        with open("/home/user/stats.json", "r") as f:
            student_data = json.load(f)
    except Exception as e:
        assert False, f"Failed to read or parse /home/user/stats.json: {e}"

    assert "t_statistic" in student_data, "t_statistic missing from stats.json"
    assert "p_value" in student_data, "p_value missing from stats.json"

    assert student_data["t_statistic"] == expected_data["t_statistic"], f"Expected t_statistic {expected_data['t_statistic']}, got {student_data['t_statistic']}"
    assert student_data["p_value"] == expected_data["p_value"], f"Expected p_value {expected_data['p_value']}, got {student_data['p_value']}"


def expected_total(mode, seed, n):
    state = seed
    total = 0.0
    modulus = 100 if mode == "A" else 105
    for _ in range(n):
        state = (state * 1103515245 + 12345) & 0x7fffffff
        total += (state % modulus) / 10.0
    return total


def read_data(path):
    with open(path, "r") as f:
        lines = f.read().splitlines()
    assert len(lines) == 50, f"{path} must contain exactly 50 lines"
    try:
        return [float(line) for line in lines]
    except ValueError as e:
        assert False, f"{path} contains a non-numeric line: {e}"


def scipy_expected(sample_a, sample_b):
    code = """
import json, sys
from scipy import stats
a = json.loads(sys.argv[1])
b = json.loads(sys.argv[2])
r = stats.ttest_ind(a, b, equal_var=False)
print(json.dumps([round(float(r.statistic), 4), round(float(r.pvalue), 4)]))
"""
    result = subprocess.run(
        ["/home/user/venv/bin/python", "-c", code,
         json.dumps(sample_a), json.dumps(sample_b)],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"Could not use scipy from the venv: {result.stderr}"
    return json.loads(result.stdout)


def assert_stats_file(sample_a, sample_b):
    with open("/home/user/stats.json", "r") as f:
        raw = f.read()
    pattern = r'^\s*\{\s*"t_statistic"\s*:\s*(-?\d+\.\d{4})\s*,\s*"p_value"\s*:\s*(-?\d+\.\d{4})\s*\}\s*$'
    assert re.fullmatch(pattern, raw), "stats.json must contain the two requested fields in order, with exactly four decimal places"
    try:
        actual = json.loads(raw)
    except Exception as e:
        assert False, f"Failed to parse stats.json: {e}"
    expected_t, expected_p = scipy_expected(sample_a, sample_b)
    assert set(actual) == {"t_statistic", "p_value"}, "stats.json has unexpected fields"
    assert actual["t_statistic"] == expected_t, f"Expected t_statistic {expected_t}, got {actual['t_statistic']}"
    assert actual["p_value"] == expected_p, f"Expected p_value {expected_p}, got {actual['p_value']}"


def test_pipeline_simulator_and_analysis_are_functional():
    # Force the pipeline to recreate every artifact it is responsible for.
    for path in ["/home/user/simulate_latency", "/home/user/data_A.txt", "/home/user/data_B.txt"]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["bash", "/home/user/pipeline.sh"],
        capture_output=True, text=True, timeout=120
    )
    assert result.returncode == 0, f"pipeline.sh failed: {result.stderr}"
    assert os.path.isfile("/home/user/simulate_latency"), "pipeline did not create simulate_latency"
    assert os.access("/home/user/simulate_latency", os.X_OK), "simulate_latency is not executable"
    with open("/home/user/simulate_latency", "rb") as f:
        assert f.read(4) == b"\x7fELF", "pipeline output is not a compiled ELF executable"

    # Exercise the compiled simulator on independently selected inputs.
    cases = [("A", 1, 1), ("B", 4294967295, 7), ("A", 123456789, 113)]
    for _ in range(6):
        cases.append((secrets.choice(["A", "B"]), secrets.randbits(32), secrets.randbelow(400) + 1))
    for mode, seed, n in cases:
        run = subprocess.run(
            ["/home/user/simulate_latency", mode, str(seed), str(n)],
            capture_output=True, text=True, timeout=10
        )
        assert run.returncode == 0, f"simulator failed for {mode}, {seed}, {n}: {run.stderr}"
        assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)\n", run.stdout), "simulator must print only one floating-point total and a newline"
        assert abs(float(run.stdout.strip()) - expected_total(mode, seed, n)) < 1e-6, f"wrong simulator result for {mode}, {seed}, {n}"

    for bad_args in [[], ["A", "1"], ["A", "1", "10", "extra"], ["C", "1", "10"]]:
        run = subprocess.run(["/home/user/simulate_latency"] + bad_args, capture_output=True, text=True, timeout=10)
        assert run.returncode != 0, f"simulator accepted invalid arguments: {bad_args}"

    data_a = read_data("/home/user/data_A.txt")
    data_b = read_data("/home/user/data_B.txt")
    expected_a = [expected_total("A", seed, 1000) for seed in range(1, 51)]
    expected_b = [expected_total("B", seed, 1000) for seed in range(1, 51)]
    for actual, expected in zip(data_a, expected_a):
        assert abs(actual - expected) < 1e-6, "data_A.txt was not generated correctly"
    for actual, expected in zip(data_b, expected_b):
        assert abs(actual - expected) < 1e-6, "data_B.txt was not generated correctly"

    # Run analyze.py on alternate verifier-provided data so fixed constants cannot pass.
    original_a = open("/home/user/data_A.txt", "rb").read()
    original_b = open("/home/user/data_B.txt", "rb").read()
    alternate_cases = [
        ([1.2, 2.8, 4.1, 5.9, 8.3, 9.7], [0.4, 3.5, 3.9, 7.6, 10.2, 12.1, 13.4]),
        ([14.0, 15.5, 13.2, 17.8, 19.1], [20.3, 18.7, 24.2, 22.9, 26.4, 21.1]),
    ]
    try:
        for sample_a, sample_b in alternate_cases:
            with open("/home/user/data_A.txt", "w") as f:
                f.write("\n".join(map(str, sample_a)) + "\n")
            with open("/home/user/data_B.txt", "w") as f:
                f.write("\n".join(map(str, sample_b)) + "\n")
            run = subprocess.run(
                ["/home/user/venv/bin/python", "/home/user/analyze.py"],
                capture_output=True, text=True, timeout=30
            )
            assert run.returncode == 0, f"analyze.py failed: {run.stderr}"
            assert os.path.isfile("/home/user/stats.json"), "analyze.py did not create stats.json"
            assert_stats_file(sample_a, sample_b)
    finally:
        with open("/home/user/data_A.txt", "wb") as f:
            f.write(original_a)
        with open("/home/user/data_B.txt", "wb") as f:
            f.write(original_b)

    # Regenerate and validate the required final result, leaving it on disk.
    run = subprocess.run(
        ["/home/user/venv/bin/python", "/home/user/analyze.py"],
        capture_output=True, text=True, timeout=30
    )
    assert run.returncode == 0, f"analyze.py failed on pipeline data: {run.stderr}"
    assert_stats_file(expected_a, expected_b)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
