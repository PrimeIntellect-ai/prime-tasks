#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import time

REPO = "/home/user/log_processor"
LOG_FILE = "/home/user/large_logs.txt"
SCRIPT_PATH = os.path.join(REPO, "process_logs.sh")


def git(*args):
    return subprocess.run(
        ["git", *args], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout.strip()


def run_script_text(script_text, timeout):
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
        f.write(script_text)
        path = f.name
    try:
        start = time.monotonic()
        try:
            result = subprocess.run(
                ["bash", path, LOG_FILE],
                capture_output=True,
                timeout=timeout,
            )
            duration = time.monotonic() - start
            return result, duration, False
        except subprocess.TimeoutExpired:
            return None, time.monotonic() - start, True
    finally:
        os.unlink(path)


def reference_output():
    v1_script = subprocess.run(
        ["git", "show", "v1.0:process_logs.sh"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    result, _, timed_out = run_script_text(v1_script, 5)
    assert not timed_out, "The v1.0 reference unexpectedly timed out."
    assert result.returncode == 0, "The v1.0 reference failed."
    return result.stdout


def derive_bad_commit():
    commits = git("rev-list", "--reverse", "v1.0..HEAD").splitlines()
    assert commits, "No commits exist after v1.0."

    for commit in commits:
        script = subprocess.run(
            ["git", "show", f"{commit}:process_logs.sh"],
            cwd=REPO,
            capture_output=True,
            text=True,
        )
        if script.returncode != 0:
            continue
        _, duration, timed_out = run_script_text(script.stdout, 1.5)
        if timed_out or duration >= 1.5:
            return commit

    raise AssertionError("Could not derive a performance-regression commit from history.")


def test_regression_report():
    report_path = "/home/user/regression_report.txt"
    assert os.path.exists(report_path), f"Report file {report_path} is missing."

    bad_commit = derive_bad_commit()
    with open(report_path, "r") as f:
        report_content = f.read()

    expected = f"Bad Commit: {bad_commit}\nStatus: fixed\n"
    assert report_content == expected, "The regression report does not have the exact required contents."


def test_process_logs_performance_and_output():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    expected_output = reference_output()
    start_time = time.monotonic()
    result = subprocess.run(
        ["bash", SCRIPT_PATH, LOG_FILE],
        capture_output=True,
        timeout=2,
    )
    duration = time.monotonic() - start_time

    assert result.returncode == 0, f"Script failed with return code {result.returncode}."
    assert duration < 1.5, f"Script execution took {duration:.2f} seconds, which is strictly >= 1.5 seconds."
    assert result.stdout == expected_output, "Script output is not byte-for-byte identical to the v1.0 output."


def test_bisection_harness_and_history():
    candidates = []
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in files:
            path = os.path.join(root, name)
            if path == SCRIPT_PATH or not name.endswith(".sh"):
                continue
            try:
                with open(path, "r", errors="replace") as f:
                    content = f.read()
            except OSError:
                continue
            if (
                "process_logs.sh" in content
                and "large_logs.txt" in content
                and "v1.0" in content
                and "1.5" in content
                and re.search(r"\b(cmp|diff)\b", content)
            ):
                candidates.append(path)

    assert candidates, "No test harness was found that checks v1.0 output and the 1.5-second limit."

    harness_passed = False
    failures = []
    for path in candidates:
        try:
            result = subprocess.run(
                ["bash", path], cwd=REPO, capture_output=True, text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            failures.append(f"{path}: timed out")
            continue
        if result.returncode == 0:
            harness_passed = True
            break
        failures.append(f"{path}: exit {result.returncode}")
    assert harness_passed, "No discovered bisection harness passes on the fixed state: " + "; ".join(failures)

    bad_commit = derive_bad_commit()
    good_neighbor = git("rev-parse", f"{bad_commit}^")
    reflog = subprocess.run(
        ["git", "reflog", "--format=%H%x00%gs"],
        cwd=REPO,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.splitlines()
    checkout_targets = {
        line.split("\x00", 1)[0]
        for line in reflog
        if "\x00" in line and line.split("\x00", 1)[1].startswith("checkout:")
    }
    assert bad_commit in checkout_targets, "Git history has no checkout evidence that the bad commit was tested during bisection."
    assert good_neighbor in checkout_targets, "Git history has no checkout evidence that the neighboring good commit was tested during bisection."


def test_git_state():
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    assert branch == "main", f"Expected to be on 'main' branch, but currently on '{branch}'."

    status = git("status", "--porcelain")
    assert not status, "There are uncommitted changes in the repository. Please commit your fix."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
