#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import textwrap
from pathlib import Path

PR_DIR = Path("/home/user/pr_review")
SOLVER = PR_DIR / "solver.py"
BUILD = PR_DIR / "build.sh"
E2E = PR_DIR / "e2e_test.sh"
CONFIG = PR_DIR / "config.env"
LOG = Path("/home/user/test_results.log")

EXPECTED_SOLVER = b'''import sys
import time
import os

RATE_FILE = "/tmp/rate_limit.txt"

def check_rate_limit():
    now = time.time()
    if not os.path.exists(RATE_FILE):
        with open(RATE_FILE, "w") as f:
            f.write(f"{now}\\n")
        return True

    with open(RATE_FILE, "r") as f:
        times = [float(x.strip()) for x in f.readlines() if x.strip()]

    # Clean up old entries (> 1 sec old)
    times = [t for t in times if now - t < 1.0]

    if len(times) >= 2:
        return False

    times.append(now)
    with open(RATE_FILE, "w") as f:
        for t in times:
            f.write(f"{t}\\n")
    return True

if __name__ == "__main__":
    if not check_rate_limit():
        print("429 Rate Limit Exceeded")
        sys.exit(1)

    # Mock constraint satisfaction logic
    target = int(sys.argv[1])
    nums = [int(x) for x in sys.argv[2:]]
    print(f"Success: Solved subset sum for target {target}")
    sys.exit(0)
'''

EXPECTED_ARGS = [
    ["10", "3", "7", "2"],
    ["15", "5", "10", "3"],
    ["8", "4", "4", "1"],
    ["20", "10", "10", "5"],
    ["12", "6", "6", "1"],
]
EXPECTED_LINES = [
    "Success: Solved subset sum for target 10",
    "Success: Solved subset sum for target 15",
    "Success: Solved subset sum for target 8",
    "Success: Solved subset sum for target 20",
    "Success: Solved subset sum for target 12",
]


def test_solver_is_unchanged():
    assert SOLVER.is_file(), f"{SOLVER} does not exist"
    assert SOLVER.read_bytes() == EXPECTED_SOLVER, "solver.py was modified"


def run_build(target_marker):
    env = os.environ.copy()
    if target_marker is None:
        env.pop("TARGET_ARCH", None)
    else:
        env["TARGET_ARCH"] = target_marker
    result = subprocess.run(
        ["bash", str(BUILD)], cwd=str(PR_DIR), env=env,
        text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"build.sh failed for TARGET_ARCH={target_marker!r}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert CONFIG.is_file(), "build.sh did not create config.env"
    return CONFIG.read_text().strip()


def test_build_sh_uses_target_arch_and_defaults_to_x86():
    assert BUILD.is_file(), f"{BUILD} does not exist"
    assert run_build(None) == "CONFIG_ARCH=x86"
    assert run_build("riscv64") == "CONFIG_ARCH=riscv64"
    # Leave the required final state behind.
    assert run_build("arm64") == "CONFIG_ARCH=arm64"


def test_config_env_content():
    config_path = "/home/user/pr_review/config.env"
    assert os.path.isfile(config_path), f"{config_path} does not exist. Did you run build.sh?"

    with open(config_path, "r") as f:
        content = f.read().strip()

    assert "CONFIG_ARCH=arm64" in content, f"Expected 'CONFIG_ARCH=arm64' in {config_path}, but found: {content}"


def test_test_results_log_exists():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you save the output of e2e_test.sh?"


def test_test_results_log_content():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read()

    success_count = content.count("Success: Solved subset sum for target")
    assert success_count >= 5, f"Expected at least 5 successful executions in the log, found {success_count}. Log content:\n{content}"
    assert "429 Rate Limit Exceeded" not in content, "Found '429 Rate Limit Exceeded' in the test results. Rate limiting was not properly avoided."


def test_e2e_test_sh_has_sleep():
    script_path = "/home/user/pr_review/e2e_test.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."

    with open(script_path, "r") as f:
        content = f.read()

    assert re.search(r'\bsleep\s+', content) is not None, "e2e_test.sh does not contain a 'sleep' command to delay executions."


def test_e2e_actually_runs_all_solver_cases_with_valid_rate_limiting():
    assert E2E.is_file(), f"{E2E} does not exist"

    probe_log = Path("/tmp/e2e_solver_probe.jsonl")
    rate_file = Path("/tmp/rate_limit.txt")
    probe_log.unlink(missing_ok=True)
    rate_file.unlink(missing_ok=True)

    original = SOLVER.read_bytes()
    original_mode = stat.S_IMODE(SOLVER.stat().st_mode)
    probe = textwrap.dedent('''\
        import json
        import os
        import sys
        import time

        RATE_FILE = "/tmp/rate_limit.txt"
        PROBE_LOG = "/tmp/e2e_solver_probe.jsonl"
        now = time.time()
        with open(PROBE_LOG, "a") as f:
            f.write(json.dumps({"time": now, "args": sys.argv[1:]}) + "\\n")

        times = []
        if os.path.exists(RATE_FILE):
            with open(RATE_FILE, "r") as f:
                times = [float(x.strip()) for x in f if x.strip()]
        times = [t for t in times if now - t < 1.0]
        if len(times) >= 2:
            print("429 Rate Limit Exceeded")
            sys.exit(1)
        times.append(now)
        with open(RATE_FILE, "w") as f:
            for value in times:
                f.write(f"{value}\\n")

        target = int(sys.argv[1])
        [int(x) for x in sys.argv[2:]]
        print(f"Success: Solved subset sum for target {target}")
    ''').encode()

    try:
        SOLVER.write_bytes(probe)
        os.chmod(SOLVER, original_mode)
        result = subprocess.run(
            ["bash", str(E2E)], cwd=str(PR_DIR),
            text=True, capture_output=True, timeout=20
        )
    finally:
        SOLVER.write_bytes(original)
        os.chmod(SOLVER, original_mode)
        rate_file.unlink(missing_ok=True)

    assert result.returncode == 0, (
        f"e2e_test.sh failed when executed:\nstdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert probe_log.is_file(), "e2e_test.sh did not execute solver.py"

    calls = [json.loads(line) for line in probe_log.read_text().splitlines() if line]
    assert [call["args"] for call in calls] == EXPECTED_ARGS, (
        f"e2e_test.sh did not execute the five required solver cases: {calls}"
    )

    times = [call["time"] for call in calls]
    for index, current in enumerate(times):
        recent = [prior for prior in times[:index] if current - prior < 1.0]
        assert len(recent) < 2, "e2e_test.sh issued more than two solver requests within one second"

    assert result.stdout.splitlines() == EXPECTED_LINES, (
        f"Unexpected e2e_test.sh stdout:\n{result.stdout}"
    )
    assert "429 Rate Limit Exceeded" not in result.stdout
    assert LOG.read_text() == result.stdout, (
        "test_results.log is not the standard output produced by the successful e2e_test.sh run"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
