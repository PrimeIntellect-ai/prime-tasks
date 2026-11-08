#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import subprocess
import time
from zoneinfo import ZoneInfo

RAW_PATH = "/home/user/raw_data.txt"
ORIGINAL_RAW = """1700000000 24.5
1700000005 88.1 ANOMALY
1700000010 23.9
1700000015 95.0 ANOMALY
1700000020 24.1
"""


def test_bare_repo_exists():
    """Check that the bare git repository exists."""
    assert os.path.isdir("/home/user/iot_update.git/refs"), "Bare git repository /home/user/iot_update.git does not exist or is not a bare repo"
    result = subprocess.run(
        ["git", "--git-dir=/home/user/iot_update.git", "rev-parse", "--is-bare-repository"],
        text=True, capture_output=True
    )
    assert result.returncode == 0 and result.stdout.strip() == "true", "/home/user/iot_update.git is not a valid bare Git repository"


def test_post_receive_hook_executable():
    """Check that the post-receive hook exists and is executable."""
    hook_path = "/home/user/iot_update.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Hook {hook_path} does not exist"
    assert os.access(hook_path, os.X_OK), f"Hook {hook_path} is not executable"


def test_deployed_files_exist():
    """Check that the deployed files exist and have correct permissions."""
    assert os.path.isfile("/home/user/deploy/parser.c"), "/home/user/deploy/parser.c does not exist"

    parser_path = "/home/user/deploy/parser"
    assert os.path.isfile(parser_path), f"{parser_path} does not exist"
    assert os.access(parser_path, os.X_OK), f"{parser_path} is not executable"

    supervisor_path = "/home/user/deploy/supervisor.sh"
    assert os.path.isfile(supervisor_path), f"{supervisor_path} does not exist"
    assert os.access(supervisor_path, os.X_OK), f"{supervisor_path} is not executable"


def test_processed_log_contents():
    """Check the contents of the processed.log file for correct formatting and logic."""
    log_path = "/home/user/processed.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist"

    with open(log_path, "r") as f:
        content = f.read()

    assert "VALIDATED: [2023-11-15 06:13:20] 24.5" in content, "Missing expected translated timestamp and value for 1700000000"
    assert "VALIDATED: [2023-11-15 06:13:30] 23.9" in content, "Missing expected translated timestamp and value for 1700000010"
    assert "VALIDATED: [2023-11-15 06:13:40] 24.1" in content, "Missing expected translated timestamp and value for 1700000020"
    assert "RESTARTING PARSER" in content, "Missing 'RESTARTING PARSER' message in log"
    assert "ANOMALY" not in content, "Log contains 'ANOMALY', which should have been filtered out"


def test_supervisor_running():
    """Check that the supervisor.sh process is running."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "supervisor.sh"]).decode("utf-8")
        assert len(output.strip()) > 0, "supervisor.sh process is not running"
    except subprocess.CalledProcessError:
        assert False, "supervisor.sh process is not running"


def tokyo_line(timestamp, remainder, prefix=""):
    rendered = datetime.datetime.fromtimestamp(timestamp, ZoneInfo("Asia/Tokyo")).strftime("%Y-%m-%d %H:%M:%S")
    return f"{prefix}[{rendered}] {remainder}"


def exact_supervisor_is_running():
    wanted = "/home/user/deploy/supervisor.sh"
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if wanted in args:
            return True
    return False


def test_parser_and_real_push_hook_workflow():
    """Exercise the compiled parser on fresh data, then deploy a fresh commit through the hook."""
    parser_path = "/home/user/deploy/parser"
    with open(parser_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "deployed parser is not a compiled ELF executable"

    base = 1577836800 + secrets.randbelow(250000000)
    parser_records = [
        (base, "17.375 SENSOR_A"),
        (base + 73, "-3.50 OK EXTRA"),
        (base + 901, "99.125 ANOMALY SENSOR_B"),
    ]
    parser_input = "".join(f"{stamp} {remainder}\n" for stamp, remainder in parser_records)
    expected = [tokyo_line(stamp, remainder) for stamp, remainder in parser_records]
    env = os.environ.copy()
    env.update({"TZ": "Asia/Tokyo", "LC_TIME": "C"})
    result = subprocess.run(
        [parser_path], input=parser_input, text=True, capture_output=True,
        env=env, timeout=5
    )
    assert result.returncode == 1, f"parser must exit with status 1 after EOF, got {result.returncode}"
    assert result.stdout.splitlines() == expected, f"parser output was incorrect on independent input: {result.stdout!r}"

    token = secrets.token_hex(12)
    source_marker = f"verifier_build_marker_{token}"
    challenge_base = base + 5000
    challenge_records = [
        (challenge_base, "41.625 SENSOR_X"),
        (challenge_base + 11, "777.0 ANOMALY SENSOR_Y"),
        (challenge_base + 29, "-8.250 VALID TAG"),
    ]
    challenge_raw = "".join(f"{stamp} {remainder}\n" for stamp, remainder in challenge_records)
    expected_valid = [
        tokyo_line(challenge_records[0][0], challenge_records[0][1], "VALIDATED: "),
        tokyo_line(challenge_records[2][0], challenge_records[2][1], "VALIDATED: "),
    ]

    try:
        with open(RAW_PATH, "w") as f:
            f.write(challenge_raw)
        with open("/home/user/processed.log", "w") as f:
            f.write("")

        with open("/home/user/workspace/parser.c", "a") as f:
            f.write(f'\nconst char {source_marker}[] = "{source_marker}";\n')
        with open("/home/user/workspace/verifier_probe.txt", "w") as f:
            f.write(token + "\n")

        git_commands = [
            ["git", "-C", "/home/user/workspace", "add", "parser.c", "verifier_probe.txt"],
            ["git", "-C", "/home/user/workspace", "-c", "user.name=Verifier Probe", "-c", "user.email=verifier@example.invalid", "-c", "commit.gpgsign=false", "commit", "-m", f"verification deployment {token}"],
            ["git", "-C", "/home/user/workspace", "push", "origin", "HEAD:master"],
        ]
        for command in git_commands:
            completed = subprocess.run(
                ["runuser", "-u", "user", "--", "env", "HOME=/home/user"] + command,
                text=True, capture_output=True, timeout=30
            )
            assert completed.returncode == 0, f"Git workflow command failed: {' '.join(command)}\n{completed.stdout}\n{completed.stderr}"

        deadline = time.time() + 15
        observed = ""
        while time.time() < deadline:
            try:
                with open("/home/user/processed.log") as f:
                    observed = f.read()
            except FileNotFoundError:
                observed = ""
            if all(line in observed for line in expected_valid) and "RESTARTING PARSER" in observed and exact_supervisor_is_running():
                break
            time.sleep(0.25)

        with open("/home/user/deploy/verifier_probe.txt") as f:
            assert f.read().strip() == token, "post-receive hook did not check out the newly pushed commit"
        with open("/home/user/deploy/parser.c") as f:
            deployed_source = f.read()
        assert source_marker in deployed_source, "post-receive hook did not deploy the newly pushed parser.c"
        with open("/home/user/deploy/parser", "rb") as f:
            deployed_binary = f.read()
        assert source_marker.encode() in deployed_binary, "post-receive hook did not compile parser from the newly pushed source"
        assert all(line in observed for line in expected_valid), f"supervisor pipeline did not process independent input correctly: {observed!r}"
        assert "ANOMALY" not in observed, "supervisor pipeline failed to filter an independently supplied ANOMALY line"
        assert "RESTARTING PARSER" in observed, "supervisor did not log a restart after parser exited with status 1"
        assert exact_supervisor_is_running(), "the deployed supervisor.sh is not running after the push"
    finally:
        with open(RAW_PATH, "w") as f:
            f.write(ORIGINAL_RAW)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
