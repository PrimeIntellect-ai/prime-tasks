#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import pwd
import re
import secrets
import subprocess

HOME = "/home/user"
LOG = f"{HOME}/telemetry.log"
CSV = f"{HOME}/memory_dashboard.csv"
SCRIPT = f"{HOME}/process_metrics.sh"
STATE = f"{HOME}/logrotate.state"
USER = pwd.getpwnam("user")


def chown_user(path):
    if os.path.exists(path):
        os.chown(path, USER.pw_uid, USER.pw_gid)


def run_as_user(argv, **kwargs):
    env = os.environ.copy()
    env["HOME"] = HOME
    env["USER"] = "user"
    env["LOGNAME"] = "user"
    return subprocess.run(
        ["runuser", "-u", "user", "--", *argv], env=env, text=True, **kwargs
    )


def clear_rotation_state():
    for path in glob.glob(f"{LOG}.*") + [STATE]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def write_user_file(path, data):
    with open(path, "w") as f:
        f.write(data)
    chown_user(path)


def test_logrotate_config():
    """Verify the logrotate configuration contains the required directives."""
    config_path = "/home/user/logrotate.conf"
    assert os.path.exists(config_path), f"{config_path} does not exist."

    with open(config_path, "r") as f:
        content = f.read()

    assert re.search(r"\bsize\s+100k\b", content), "logrotate.conf is missing 'size 100k'."
    assert re.search(r"\brotate\s+4\b", content), "logrotate.conf is missing 'rotate 4'."
    assert re.search(r"\bcompress\b", content), "logrotate.conf is missing 'compress'."
    assert re.search(r"\bcopytruncate\b", content), "logrotate.conf is missing 'copytruncate'."

    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if line.startswith("su "):
            fields = line.split()
            assert all(not field.startswith("/") for field in fields[1:]), \
                "The su directive must not contain absolute paths."


def test_automation_script():
    """Verify the automation script exists, is executable, and contains required commands."""
    script_path = "/home/user/process_metrics.sh"
    assert os.path.exists(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "/home/user/parser" in content, "process_metrics.sh does not call /home/user/parser."
    assert "logrotate -s /home/user/logrotate.state /home/user/logrotate.conf" in content, \
        "process_metrics.sh does not call logrotate with the correct arguments."


def test_crontab_configuration():
    """Verify the user's crontab has the correct scheduled task."""
    try:
        output = subprocess.check_output(["crontab", "-l"], stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError:
        output = ""

    pattern = r"\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/process_metrics\.sh"
    assert re.search(pattern, output), "Crontab does not contain the correct schedule for process_metrics.sh."
    active_lines = [line.strip() for line in output.splitlines()
                    if line.strip() and not line.lstrip().startswith("#")]
    assert any(re.fullmatch(pattern, line) for line in active_lines), \
        "The required cron schedule must be an active crontab entry."


def test_parser_and_execution():
    """Retain the original parser assertions and execute the automation script."""
    parser_source = "/home/user/parser.rs"
    parser_path = "/home/user/parser"
    assert os.path.isfile(parser_source), f"{parser_source} does not exist."
    assert os.path.isfile(parser_path), f"{parser_path} binary does not exist."
    assert os.access(parser_path, os.X_OK), f"{parser_path} is not executable."
    with open(parser_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled parser is not an ELF binary."

    clear_rotation_state()
    try:
        os.remove(CSV)
    except FileNotFoundError:
        pass

    dummy_logs = (
        "[2023-11-01T10:00:00Z] INFO - disk_space: 45.2\n"
        "[2023-11-01T10:00:01Z] INFO - memory_utilization: 82.1\n"
        "[2023-11-01T10:00:02Z] WARN - cpu_load: 99.9\n"
        "[2023-11-01T10:00:03Z] INFO - memory_utilization: 83.4\n"
    )
    write_user_file(LOG, dummy_logs)

    result = run_as_user(["bash", SCRIPT], capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert os.path.exists(CSV), f"{CSV} was not created."

    with open(CSV, "r") as f:
        csv_content = f.read()

    assert "2023-11-01T10:00:01Z,82.1" in csv_content, "CSV is missing the first memory_utilization metric."
    assert "2023-11-01T10:00:03Z,83.4" in csv_content, "CSV is missing the second memory_utilization metric."
    assert "45.2" not in csv_content, "CSV incorrectly contains metrics other than memory_utilization."
    assert "99.9" not in csv_content, "CSV incorrectly contains metrics other than memory_utilization."


def test_parser_randomized_behavior_and_append():
    """Exercise parsing on unpredictable values and require exact ordered CSV output."""
    token = secrets.token_hex(6)
    values = [f"{secrets.randbelow(90000) + 10000}.{secrets.randbelow(1000000):06d}" for _ in range(5)]
    timestamps = [f"2026-09-11T12:34:{i:02d}Z" for i in range(10, 15)]
    expected = [f"seed-{token},preserved"]
    lines = []

    for i, (timestamp, value) in enumerate(zip(timestamps, values)):
        lines.append(f"[{timestamp}] INFO - disk_space: {token}-{i}\n")
        lines.append(f"[{timestamp}] WARN - memory_utilization_extra: {value}\n")
        lines.append(f"[{timestamp}] DEBUG - memory_utilization: {value}\n")
        expected.append(f"{timestamp},{value}")
        lines.append(f"[{timestamp}] INFO - cpu_memory_utilization: {value}\n")

    write_user_file(LOG, "".join(lines))
    write_user_file(CSV, expected[0] + "\n")
    result = run_as_user([f"{HOME}/parser"], capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr

    with open(CSV) as f:
        actual = f.read().splitlines()
    assert actual == expected, f"Unexpected parser output: {actual!r}"


def make_large_log(marker, target=120000):
    first = f"[2026-09-11T13:00:00Z] INFO - memory_utilization: {marker}\n"
    filler = "[2026-09-11T13:00:01Z] INFO - disk_space: 12.34\n"
    data = first
    while len(data.encode()) <= target:
        data += filler
    write_user_file(LOG, data)


def rotated_files():
    return [p for p in glob.glob(f"{LOG}.*") if os.path.isfile(p)]


def test_real_rotation_order_size_compression_and_retention():
    """Run the automation and verify parser ordering plus real logrotate behavior."""
    clear_rotation_state()
    write_user_file(CSV, "")

    # A log below 100k must not rotate.
    small_marker = secrets.token_hex(8)
    make_large_log(small_marker, target=80000)
    result = run_as_user([SCRIPT], capture_output=True)
    assert result.returncode == 0, result.stdout + result.stderr
    assert rotated_files() == [], "A telemetry log below 100k was rotated."
    assert os.path.getsize(LOG) > 0, "The below-threshold log was unexpectedly truncated."

    # Reset state and use bash tracing once to establish that both required commands
    # are actually executed in the required order.
    clear_rotation_state()
    write_user_file(CSV, "")
    markers = []
    marker = f"{secrets.randbelow(900000) + 100000}.{secrets.randbelow(100000):05d}"
    markers.append(marker)
    make_large_log(marker)
    inode_before = os.stat(LOG).st_ino
    traced = run_as_user(["bash", "-x", SCRIPT], capture_output=True)
    assert traced.returncode == 0, traced.stdout + traced.stderr
    trace = traced.stderr
    parser_pos = trace.find("+ /home/user/parser")
    rotate_pos = trace.find("+ logrotate -s /home/user/logrotate.state /home/user/logrotate.conf")
    assert parser_pos >= 0, "The automation script did not execute /home/user/parser."
    assert rotate_pos >= 0, "The automation script did not execute the required logrotate command."
    assert parser_pos < rotate_pos, "The parser must execute before logrotate."

    assert os.stat(LOG).st_ino == inode_before, "Rotation did not preserve the active log inode (copytruncate)."
    assert os.path.getsize(LOG) == 0, "copytruncate did not truncate the active telemetry log."
    with open(CSV) as f:
        assert f"2026-09-11T13:00:00Z,{marker}" in f.read(), \
            "The parser did not process the log before it was rotated."

    # Produce more rotations than the retention count.
    for _ in range(5):
        marker = f"{secrets.randbelow(900000) + 100000}.{secrets.randbelow(100000):05d}"
        markers.append(marker)
        make_large_log(marker)
        inode_before = os.stat(LOG).st_ino
        result = run_as_user([SCRIPT], capture_output=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert os.stat(LOG).st_ino == inode_before, "copytruncate was not used."
        assert os.path.getsize(LOG) == 0, "The active log was not truncated after rotation."

    archives = rotated_files()
    assert len(archives) == 4, f"Expected exactly 4 backup copies, found {archives!r}."
    assert all(path.endswith(".gz") for path in archives), \
        f"All retained backups must be compressed: {archives!r}"

    archived_text = ""
    for path in archives:
        with gzip.open(path, "rt") as f:
            archived_text += f.read()

    for marker in markers[-4:]:
        assert marker in archived_text, f"A retained rotated log is missing marker {marker}."
    for marker in markers[:-4]:
        assert marker not in archived_text, f"A backup older than four rotations was retained: {marker}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
