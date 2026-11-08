#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import secrets
import subprocess

import pytest

DETECTOR = "/home/user/detector"
SOURCE = "/home/user/detector.cpp"
MONITOR = "/home/user/monitor.sh"
ACCESS_LOG = "/var/log/nginx/access.log"
ALERT_LOG = "/home/user/alerts.log"


def expected_exit(entries):
    for end in range(9, len(entries)):
        window = entries[end - 9:end + 1]
        if sum(e["bytes"] for e in window) > 100000 and sum(e["status"] >= 400 for e in window) > 3:
            return 1
    return 0


def encode_entries(entries):
    return "".join(json.dumps(e, separators=(",", ":")) + "\n" for e in entries)


def run_detector(entries, timeout=5):
    return subprocess.run(
        [DETECTOR], input=encode_entries(entries), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    ).returncode


def test_detector_exists():
    assert os.path.isfile(DETECTOR), "Detector executable missing at /home/user/detector"
    assert os.access(DETECTOR, os.X_OK), "Detector is not executable"


def test_detector_source_and_binary_kind():
    assert os.path.isfile(SOURCE), "C++ source missing at /home/user/detector.cpp"
    assert os.path.getsize(SOURCE) > 0, "C++ source is empty"
    with open(DETECTOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector must be a compiled executable"


def test_monitor_script_exists():
    assert os.path.isfile(MONITOR), "Monitor script missing at /home/user/monitor.sh"


def cron_sources():
    user_lines = []
    system_lines = []
    result = subprocess.run(["crontab", "-l", "-u", "user"], capture_output=True, text=True)
    if result.returncode == 0:
        user_lines.extend(result.stdout.splitlines())
    if os.path.isfile("/etc/crontab"):
        with open("/etc/crontab", "r") as f:
            system_lines.extend(f.read().splitlines())
    for cron_file in glob.glob("/etc/cron.d/*"):
        if os.path.isfile(cron_file):
            with open(cron_file, "r") as f:
                system_lines.extend(f.read().splitlines())
    return user_lines, system_lines


def test_cron_job_setup():
    cron_content = ""
    result = subprocess.run(["crontab", "-l", "-u", "user"], capture_output=True, text=True)
    if result.returncode == 0:
        cron_content += result.stdout
    if os.path.isfile("/etc/crontab"):
        with open("/etc/crontab", "r") as f:
            cron_content += f.read()
    for cron_file in glob.glob("/etc/cron.d/*"):
        if os.path.isfile(cron_file):
            with open(cron_file, "r") as f:
                cron_content += f.read()
    assert MONITOR in cron_content, "Monitor script /home/user/monitor.sh is not scheduled in any cron configuration"


def test_cron_is_active_every_minute_for_user():
    user_lines, system_lines = cron_sources()
    valid = False
    for line in user_lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) >= 6 and fields[:5] == ["*"] * 5 and MONITOR in " ".join(fields[5:]):
            valid = True
    for line in system_lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) >= 7 and fields[:5] == ["*"] * 5 and fields[5] == "user" and MONITOR in " ".join(fields[6:]):
            valid = True
    assert valid, "An active every-minute cron entry for user must run /home/user/monitor.sh"


def test_adversarial_corpus_evil():
    evil_files = glob.glob("/app/corpus/evil/*.json")
    assert len(evil_files) > 0, "No evil corpus files found in /app/corpus/evil/"
    bypassed = []
    for f in evil_files:
        with open(f, "r") as stdin_file:
            result = subprocess.run([DETECTOR], stdin=stdin_file)
            if result.returncode != 1:
                bypassed.append(os.path.basename(f))
    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}"


def test_adversarial_corpus_clean():
    clean_files = glob.glob("/app/corpus/clean/*.json")
    assert len(clean_files) > 0, "No clean corpus files found in /app/corpus/clean/"
    modified = []
    for f in clean_files:
        with open(f, "r") as stdin_file:
            result = subprocess.run([DETECTOR], stdin=stdin_file)
            if result.returncode != 0:
                modified.append(os.path.basename(f))
    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified: {', '.join(modified)}"


def test_detector_hidden_rolling_cases():
    cases = []
    cases.append([{"status": 500 if i < 4 else 200, "bytes": 20000} for i in range(9)])
    cases.append([{"status": 500 if i < 4 else 200, "bytes": 10000} for i in range(10)])
    cases.append([{"status": 500 if i < 3 else 200, "bytes": 10001} for i in range(10)])
    cases.append([{"status": 200, "bytes": 1}] * 7 +
                 [{"status": 500 if i < 4 else 200, "bytes": 13000} for i in range(10)])

    rng = secrets.SystemRandom()
    for _ in range(60):
        length = rng.randrange(0, 90)
        entries = []
        for _ in range(length):
            entries.append({
                "status": rng.choice([200, 201, 302, 399, 400, 401, 404, 500, 503]),
                "bytes": rng.randrange(0, 24001),
            })
        cases.append(entries)

    for index, entries in enumerate(cases):
        actual = run_detector(entries)
        expected = expected_exit(entries)
        assert actual == expected, f"Hidden rolling case {index}: expected exit {expected}, got {actual}"


def test_detector_exits_as_soon_as_anomaly_arrives():
    entries = [{"status": 500 if i < 4 else 200, "bytes": 10001} for i in range(10)]
    proc = subprocess.Popen([DETECTOR], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        proc.stdin.write(encode_entries(entries))
        proc.stdin.flush()
        code = proc.wait(timeout=2)
        assert code == 1, f"Detector did not immediately exit 1 after an anomalous window (got {code})"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if proc.stdin and not proc.stdin.closed:
            proc.stdin.close()


def test_detector_handles_large_stream_to_eof():
    entries = ({"status": 200, "bytes": 100} for _ in range(120000))
    payload = "".join(json.dumps(e) + "\n" for e in entries)
    result = subprocess.run([DETECTOR], input=payload, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, "Large clean stream was not processed correctly"


def read_optional(path):
    if not os.path.lexists(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def restore_optional(path, data):
    if data is None:
        if os.path.lexists(path):
            os.unlink(path)
    else:
        with open(path, "wb") as f:
            f.write(data)


def test_monitor_tails_100_invokes_detector_and_alerts_exactly():
    old_access = read_optional(ACCESS_LOG)
    old_alerts = read_optional(ALERT_LOG)
    backup = "/tmp/verifier_detector_backup"
    capture = "/tmp/verifier_monitor_capture"
    code_file = "/tmp/verifier_monitor_code"
    if os.path.lexists(backup):
        os.unlink(backup)

    rng = secrets.SystemRandom()
    lines = []
    for i in range(137):
        obj = {"status": rng.choice([200, 404, 500]), "bytes": rng.randrange(1, 30000), "nonce": rng.getrandbits(64)}
        lines.append((json.dumps(obj, separators=(",", ":")) + "\n").encode())
    expected_tail = b"".join(lines[-100:])

    os.replace(DETECTOR, backup)
    try:
        with open(DETECTOR, "w") as f:
            f.write("#!/bin/bash\ncat > /tmp/verifier_monitor_capture\ncode=$(cat /tmp/verifier_monitor_code)\nexit \"$code\"\n")
        os.chmod(DETECTOR, 0o755)
        with open(ACCESS_LOG, "wb") as f:
            f.write(b"".join(lines))
        with open(ALERT_LOG, "wb") as f:
            f.write(b"PREEXISTING\n")

        with open(code_file, "w") as f:
            f.write("1\n")
        result = subprocess.run(["bash", MONITOR], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert os.path.isfile(capture), "Monitor did not invoke /home/user/detector"
        with open(capture, "rb") as f:
            assert f.read() == expected_tail, "Monitor did not pipe exactly the last 100 access-log lines to detector"
        with open(ALERT_LOG, "rb") as f:
            assert f.read() == b"PREEXISTING\nALERT DETECTED\n", "Monitor did not append the exact alert string for detector exit 1"

        os.unlink(capture)
        with open(code_file, "w") as f:
            f.write("0\n")
        result = subprocess.run(["bash", MONITOR], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert os.path.isfile(capture), "Monitor did not invoke detector on a clean run"
        with open(ALERT_LOG, "rb") as f:
            assert f.read() == b"PREEXISTING\nALERT DETECTED\n", "Monitor appended an alert when detector exited 0"
    finally:
        if os.path.lexists(DETECTOR):
            os.unlink(DETECTOR)
        os.replace(backup, DETECTOR)
        restore_optional(ACCESS_LOG, old_access)
        restore_optional(ALERT_LOG, old_alerts)
        for path in (capture, code_file):
            if os.path.lexists(path):
                os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
