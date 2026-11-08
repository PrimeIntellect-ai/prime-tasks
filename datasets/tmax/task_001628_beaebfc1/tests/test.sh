#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import os
import re
import shutil
import subprocess
import uuid

SCRIPT_PATH = "/home/user/monitor/integrity_monitor.sh"
BASELINE_PATH = "/home/user/monitor/baseline.md5"
ALERTS_PATH = "/home/user/monitor/alerts.log"
PROTECTED_DIR = "/home/user/protected_data"

ALERT_RE = re.compile(
    r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] ALERT: "
    r"(/home/user/protected_data/.+) modified or created$"
)


def run_monitor():
    subprocess.run([SCRIPT_PATH], check=True, timeout=20)


def remove_monitor_state():
    for path in [BASELINE_PATH, ALERTS_PATH,
                 ALERTS_PATH + ".1", ALERTS_PATH + ".2", ALERTS_PATH + ".3"]:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.remove(path)


def clear_protected_dir():
    for name in os.listdir(PROTECTED_DIR):
        path = os.path.join(PROTECTED_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)


def expected_hashes():
    result = {}
    for root, _, files in os.walk(PROTECTED_DIR):
        for name in files:
            path = os.path.normpath(os.path.join(root, name))
            if os.path.isfile(path):
                with open(path, "rb") as f:
                    result[path] = hashlib.md5(f.read()).hexdigest()
    return result


def parse_baseline():
    assert os.path.isfile(BASELINE_PATH), "Baseline file does not exist."
    parsed = {}
    with open(BASELINE_PATH, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if not line:
                continue
            tokens = line.split()
            hash_positions = [i for i, token in enumerate(tokens)
                              if re.fullmatch(r"[0-9a-fA-F]{32}", token)]
            assert len(hash_positions) == 1, f"Invalid baseline entry: {line!r}"
            pos = hash_positions[0]
            digest = tokens[pos].lower()
            path_tokens = tokens[:pos] + tokens[pos + 1:]
            assert len(path_tokens) == 1, f"Invalid or ambiguous baseline path: {line!r}"
            path = path_tokens[0]
            if path.startswith("*"):
                path = path[1:]
            if not os.path.isabs(path):
                if path.startswith("./"):
                    path = path[2:]
                path = os.path.join(PROTECTED_DIR, path)
            path = os.path.normpath(path)
            assert path == PROTECTED_DIR or path.startswith(PROTECTED_DIR + os.sep), \
                f"Baseline contains a path outside the target directory: {path}"
            assert path not in parsed, f"Duplicate baseline entry for {path}"
            parsed[path] = digest
    return parsed


def assert_baseline_current():
    assert parse_baseline() == expected_hashes(), \
        "baseline.md5 does not exactly reflect all current regular files and hashes."


def read_alert_paths(path=ALERTS_PATH):
    assert os.path.isfile(path), f"Expected log file {path}"
    result = []
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            match = ALERT_RE.fullmatch(line)
            assert match, f"Alert line format incorrect: {line}"
            datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S")
            result.append(match.group(2))
    return result


def test_script_exists_and_executable():
    """Verify that the script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_functionality():
    """Preserve the original baseline, fixed-file, and basic rotation assertions."""
    if os.path.exists(BASELINE_PATH):
        os.remove(BASELINE_PATH)
    if os.path.exists(ALERTS_PATH):
        os.remove(ALERTS_PATH)
    for ext in [".1", ".2", ".3"]:
        if os.path.exists(ALERTS_PATH + ext):
            os.remove(ALERTS_PATH + ext)

    subprocess.run([SCRIPT_PATH], check=True)
    assert os.path.isfile(BASELINE_PATH), "Baseline file was not created on first run."
    if os.path.exists(ALERTS_PATH):
        with open(ALERTS_PATH, 'r') as f:
            lines = f.readlines()
            assert len(lines) == 0, "Alerts log should be empty or not created on first run."

    file1 = os.path.join(PROTECTED_DIR, "file1.txt")
    with open(file1, "w") as f:
        f.write("changed\n")

    subprocess.run([SCRIPT_PATH], check=True)
    assert os.path.isfile(ALERTS_PATH), "Alerts log was not created after modification."

    with open(ALERTS_PATH, 'r') as f:
        lines = f.readlines()
        assert len(lines) >= 1, "Alerts log is empty after modification."
        last_line = lines[-1].strip()
        regex = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ALERT: \/home\/user\/protected_data\/file1\.txt modified or created$"
        assert re.match(regex, last_line), f"Alert line format incorrect: {last_line}"

    with open(ALERTS_PATH, "a") as f:
        for i in range(1, 6):
            f.write(f"Dummy log line {i}\n")

    file3 = os.path.join(PROTECTED_DIR, "file3.txt")
    with open(file3, "w") as f:
        f.write("new file\n")

    subprocess.run([SCRIPT_PATH], check=True)

    assert os.path.isfile(ALERTS_PATH + ".1"), "Log rotation failed: alerts.log.1 not created."

    with open(ALERTS_PATH, 'r') as f:
        lines = f.readlines()
        assert len(lines) == 1, f"Expected exactly 1 line in new alerts.log after rotation, got {len(lines)}"
        last_line = lines[0].strip()
        regex = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] ALERT: \/home\/user\/protected_data\/file3\.txt modified or created$"
        assert re.match(regex, last_line), f"Alert line format incorrect after rotation: {last_line}"


def test_randomized_full_functionality_and_rotation_chain():
    """Exercise arbitrary nested files, exact baselines, updates, and all archives."""
    clear_protected_dir()
    remove_monitor_state()

    token = uuid.uuid4().hex
    unchanged = os.path.join(PROTECTED_DIR, f"stable_{token}.dat")
    changed = os.path.join(PROTECTED_DIR, f"change_{token}.cfg")
    deleted = os.path.join(PROTECTED_DIR, f"delete_{token}.tmp")
    nested_dir = os.path.join(PROTECTED_DIR, f"nested_{token}", "deeper")
    nested = os.path.join(nested_dir, f"nested_{token}.bin")
    os.makedirs(nested_dir)

    contents = {
        unchanged: os.urandom(137),
        changed: os.urandom(211),
        deleted: os.urandom(89),
        nested: os.urandom(313),
    }
    for path, data in contents.items():
        with open(path, "wb") as f:
            f.write(data)

    run_monitor()
    assert_baseline_current()
    if os.path.exists(ALERTS_PATH):
        assert os.path.getsize(ALERTS_PATH) == 0, \
            "Initial baseline creation must not log alerts."

    baseline_before = open(BASELINE_PATH, "rb").read()
    run_monitor()
    assert open(BASELINE_PATH, "rb").read() == baseline_before, \
        "An unchanged run unexpectedly rewrote baseline contents."
    if os.path.exists(ALERTS_PATH):
        assert os.path.getsize(ALERTS_PATH) == 0, \
            "An unchanged run must not log alerts."

    new_nested = os.path.join(nested_dir, f"new_{uuid.uuid4().hex}.txt")
    with open(changed, "wb") as f:
        f.write(os.urandom(407))
    with open(new_nested, "wb") as f:
        f.write(os.urandom(509))
    os.remove(deleted)

    run_monitor()
    assert set(read_alert_paths()) == {changed, new_nested}, \
        "The monitor did not report exactly the arbitrary changed and newly created files."
    assert_baseline_current()

    prior_log = open(ALERTS_PATH, "rb").read()
    run_monitor()
    assert open(ALERTS_PATH, "rb").read() == prior_log, \
        "Files were re-alerted even though the baseline should have been updated."
    assert_baseline_current()

    old_current = b"current-1\ncurrent-2\ncurrent-3\ncurrent-4\ncurrent-5\n"
    old_one = b"archive-one-" + os.urandom(16) + b"\n"
    old_two = b"archive-two-" + os.urandom(16) + b"\n"
    old_three = b"archive-three-" + os.urandom(16) + b"\n"
    for path, data in [(ALERTS_PATH, old_current),
                       (ALERTS_PATH + ".1", old_one),
                       (ALERTS_PATH + ".2", old_two),
                       (ALERTS_PATH + ".3", old_three)]:
        with open(path, "wb") as f:
            f.write(data)

    rotate_changed = unchanged
    rotate_new = os.path.join(PROTECTED_DIR, f"rotate_new_{uuid.uuid4().hex}.dat")
    with open(rotate_changed, "wb") as f:
        f.write(os.urandom(601))
    with open(rotate_new, "wb") as f:
        f.write(os.urandom(701))

    run_monitor()
    assert open(ALERTS_PATH + ".1", "rb").read() == old_current, \
        "alerts.log was not moved intact to alerts.log.1."
    assert open(ALERTS_PATH + ".2", "rb").read() == old_one, \
        "alerts.log.1 was not moved intact to alerts.log.2."
    assert open(ALERTS_PATH + ".3", "rb").read() == old_two, \
        "alerts.log.2 was not moved intact to alerts.log.3."
    assert set(read_alert_paths()) == {rotate_changed, rotate_new}, \
        "New alerts were not written to a fresh log after rotation."
    assert_baseline_current()

    four_lines = b"one\ntwo\nthree\nfour\n"
    with open(ALERTS_PATH, "wb") as f:
        f.write(four_lines)
    archive_snapshots = {}
    for ext in [".1", ".2", ".3"]:
        archive_snapshots[ext] = open(ALERTS_PATH + ext, "rb").read()

    with open(nested, "wb") as f:
        f.write(os.urandom(811))
    run_monitor()
    for ext, data in archive_snapshots.items():
        assert open(ALERTS_PATH + ext, "rb").read() == data, \
            "A log with fewer than five lines must not rotate before appending."
    with open(ALERTS_PATH, "rb") as f:
        final_lines = f.readlines()
    assert len(final_lines) == 5 and b"".join(final_lines[:4]) == four_lines, \
        "The alert was not appended to the unrotated four-line log."
    assert read_alert_paths(ALERTS_PATH)[-1:] == [nested]
    assert_baseline_current()


def test_cron_job():
    """Verify that the cron job is correctly scheduled and invokes the script."""
    result = subprocess.run(["crontab", "-l"], capture_output=True, text=True)
    output = result.stdout
    regex = r"\*/5\s+\*\s+\*\s+\*\s+\*\s+.*\/home\/user\/monitor\/integrity_monitor.sh"
    assert re.search(regex, output), "Cron job not found or incorrect format in crontab."

    valid = False
    command_re = re.compile(
        r"^(?:(?:/bin/)?(?:bash|sh)\s+)?"
        r"/home/user/monitor/integrity_monitor\.sh(?:\s|$)"
    )
    for raw in output.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(None, 5)
        if len(fields) == 6 and fields[:5] == ["*/5", "*", "*", "*", "*"]:
            if command_re.match(fields[5]):
                valid = True
                break
    assert valid, "No active every-five-minutes cron entry actually invokes the monitor script."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
