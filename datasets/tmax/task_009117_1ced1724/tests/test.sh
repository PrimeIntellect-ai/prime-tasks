#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import shutil
import signal
import stat
import subprocess

SCRIPT_PATH = "/home/user/process_logs_fixed.sh"
LOG_DIR = "/home/user/logs"
RESULTS_DIR = "/home/user/results"
REPORT_PATH = "/home/user/final_report.txt"


def test_fixed_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Fixed script {SCRIPT_PATH} is missing."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Fixed script {SCRIPT_PATH} is not executable."


def test_fixed_script_contains_parallelization():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "&" in content, "The parallelization logic ('&') was removed from the script."
    assert "wait" in content, "The parallelization logic ('wait') was removed from the script."


def write_logs(files):
    shutil.rmtree(LOG_DIR, ignore_errors=True)
    os.makedirs(LOG_DIR)
    for name, lines in files.items():
        with open(os.path.join(LOG_DIR, name), "w") as f:
            f.write("\n".join(lines) + "\n")


def run_script_and_check(files):
    write_logs(files)
    shutil.rmtree(RESULTS_DIR, ignore_errors=True)
    if os.path.lexists(REPORT_PATH):
        os.unlink(REPORT_PATH)

    total_lines = sum(len(lines) for lines in files.values())
    total_errors = sum(
        1 for lines in files.values() for line in lines if "ERROR" in line.split()
    )
    expected = f"Rate: {total_errors * 100 // total_lines}"

    user = pwd.getpwnam("user")

    def demote():
        os.setsid()
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    proc = subprocess.Popen(
        [SCRIPT_PATH],
        cwd="/home/user",
        env={**os.environ, "LOG_DIR": LOG_DIR},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        preexec_fn=demote,
    )
    try:
        stdout, stderr = proc.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise AssertionError("The fixed script hung instead of completing.")

    assert proc.returncode == 0, (
        f"The fixed script exited with status {proc.returncode}.\n"
        f"stdout:\n{stdout}\nstderr:\n{stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Final report {REPORT_PATH} is missing."
    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()
    assert content == expected, (
        f"Expected final report to contain '{expected}', but got '{content}'."
    )


def test_final_report_content():
    # First exercise the script against the logs supplied by the task (7/16 = 43%).
    run_script_and_check({
        "app1.log": [
            "INFO Starting app",
            "INFO Loading config",
            "ERROR Failed to connect to DB",
            "INFO Retrying",
            "ERROR Failed to connect to DB",
            "INFO Giving up",
        ],
        "app2.log": [
            "INFO Starting app2",
            "ERROR Null pointer exception",
            "ERROR Timeout",
            "INFO Done",
        ],
        "app3.log": [
            "INFO Request received",
            "ERROR Invalid parameters",
            "INFO Processing",
            "ERROR Disk full",
            "ERROR Write failed",
            "INFO Done",
        ],
    })

    # Exercise it again with a runtime-selected ratio so a fabricated fixed report
    # cannot satisfy the verifier without actually processing the logs.
    rng = secrets.SystemRandom()
    while True:
        total = rng.randint(16, 32)
        errors = rng.randint(4, total - 4)
        rate = errors * 100 // total
        if rate not in (43, 62):
            break

    lines = [f"ERROR generated failure {i}" for i in range(errors)]
    lines += [f"INFO generated success {i}" for i in range(total - errors)]
    rng.shuffle(lines)
    generated = {f"generated{i}.log": [] for i in range(4)}
    for i, line in enumerate(lines):
        generated[f"generated{i % 4}.log"].append(line)
    run_script_and_check(generated)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
