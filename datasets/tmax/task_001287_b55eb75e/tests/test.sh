#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import tempfile

RESULTS_PATH = "/home/user/debugging_results.json"
REPO_DIR = "/home/user/log_processor"
SCRIPT_PATH = os.path.join(REPO_DIR, "process_logs.py")
DAILY_LOG = "/home/user/data/daily.log"


def load_results():
    with open(RESULTS_PATH, "r") as f:
        return json.load(f)


def bad_commit_hash():
    result = subprocess.run(
        ["git", "log", "--grep=Optimize apdex calculation", "--format=%H"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        check=True,
    )
    expected_hash = result.stdout.strip()
    assert expected_hash != "", "Could not find the expected bad commit in the git history."
    return expected_hash


def run_script(script_path, lines):
    with tempfile.NamedTemporaryFile("w", delete=False) as log_file:
        for line in lines:
            log_file.write(line.rstrip("\r\n") + "\n")
        log_path = log_file.name

    try:
        result = subprocess.run(
            ["python3", script_path, log_path],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert result.returncode == 0, (
            f"{script_path} failed with exit code {result.returncode}: {result.stderr}"
        )
        try:
            return float(result.stdout.strip())
        except ValueError:
            assert False, f"Expected a numeric APDEX score, got: {result.stdout!r}"
    finally:
        os.unlink(log_path)


def test_debugging_results_json_exists():
    assert os.path.isfile(RESULTS_PATH), "The file /home/user/debugging_results.json does not exist."


def test_debugging_results_json_format():
    try:
        data = load_results()
    except json.JSONDecodeError:
        assert False, "/home/user/debugging_results.json is not valid JSON."

    expected_keys = {"bad_commit", "minimized_log_line", "corrected_formula_code"}
    assert set(data.keys()) == expected_keys, f"JSON must contain exactly the keys: {expected_keys}"
    assert all(isinstance(data[key], str) for key in expected_keys), "All JSON values must be strings."


def test_bad_commit_hash():
    data = load_results()
    expected_hash = bad_commit_hash()
    assert data["bad_commit"] == expected_hash, (
        f"Incorrect bad_commit. Expected {expected_hash}, got {data['bad_commit']}"
    )


def test_minimized_log_line():
    data = load_results()
    reported_line = data["minimized_log_line"].strip()
    assert reported_line, "minimized_log_line must not be empty."
    assert "\n" not in reported_line and "\r" not in reported_line, (
        "minimized_log_line must contain exactly one log line."
    )

    with open(DAILY_LOG, "r") as f:
        source_lines = [line.rstrip("\r\n") for line in f]
    assert reported_line in source_lines, (
        "minimized_log_line is not an exact line from /home/user/data/daily.log."
    )

    bad_source = subprocess.run(
        ["git", "show", f"{bad_commit_hash()}:process_logs.py"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as bad_script:
        bad_script.write(bad_source)
        bad_script_path = bad_script.name

    try:
        score = run_script(bad_script_path, [reported_line])
    finally:
        os.unlink(bad_script_path)

    assert score < 0.0 or score > 1.0, (
        f"The reported single line does not reproduce an invalid score at the bad commit; got {score}."
    )


def test_corrected_formula_code():
    data = load_results()
    formula_code = data["corrected_formula_code"]

    test_env = {
        "satisfied": 80,
        "tolerating": 15,
        "total": 100,
    }
    expected_result = 0.875

    try:
        exec(formula_code, {}, test_env)
    except Exception as e:
        assert False, f"Failed to execute corrected_formula_code: {e}"

    if "apdex" in test_env:
        result = test_env["apdex"]
    else:
        try:
            result = eval(formula_code, {}, test_env)
        except Exception as e:
            assert False, (
                "Could not determine the result of the formula. Ensure it assigns to "
                f"'apdex' or is a pure expression. Error: {e}"
            )

    assert abs(result - expected_result) < 1e-6, (
        f"The corrected formula yielded {result}, but expected {expected_result}."
    )

    with open(SCRIPT_PATH, "r") as f:
        source_lines = [line.strip() for line in f]
    assert formula_code.strip() in source_lines, (
        "corrected_formula_code must be an exact code line present in process_logs.py."
    )


def test_process_logs_is_corrected_and_executable():
    assert os.path.exists(SCRIPT_PATH), "process_logs.py does not exist."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), "process_logs.py must be a regular file."

    rng = secrets.SystemRandom()
    cases = [(80, 15, 100), (100, 0, 100), (0, 100, 100), (0, 0, 100)]
    for _ in range(8):
        total = rng.randint(10, 10000)
        satisfied = rng.randint(0, total)
        tolerating = rng.randint(0, total - satisfied)
        cases.append((satisfied, tolerating, total))

    generated_lines = []
    expected_scores = []
    for satisfied, tolerating, total in cases:
        line = f"2026-01-01 00:00 INFO {satisfied} {tolerating} {total}"
        expected = (satisfied + (tolerating / 2.0)) / total
        actual = run_script(SCRIPT_PATH, [line])
        assert abs(actual - expected) < 1e-9, (
            f"process_logs.py returned {actual} for {line!r}, expected {expected}."
        )
        generated_lines.append(line)
        expected_scores.append(expected)

    combined_actual = run_script(SCRIPT_PATH, generated_lines)
    combined_expected = max(expected_scores)
    assert abs(combined_actual - combined_expected) < 1e-9, (
        f"process_logs.py returned {combined_actual} for a multi-line log, expected {combined_expected}."
    )

    with open(DAILY_LOG, "r") as f:
        daily_lines = [line.rstrip("\r\n") for line in f]
    daily_expected = max(
        (int(line.split()[3]) + int(line.split()[4]) / 2.0) / int(line.split()[5])
        for line in daily_lines
        if len(line.split()) >= 6
    )
    daily_actual = run_script(SCRIPT_PATH, daily_lines)
    assert abs(daily_actual - daily_expected) < 1e-9, (
        f"process_logs.py returned {daily_actual} for daily.log, expected {daily_expected}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
