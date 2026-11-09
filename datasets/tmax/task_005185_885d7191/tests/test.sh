#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import math
import os
import re
import shutil
import subprocess
import uuid

LOGS_DIR = "/home/user/edge_storage/logs"
STORAGE_DIR = "/home/user/edge_storage"
STATUS_FILE = "/home/user/logrotate.status"
OUTBOX = "/home/user/mail_outbox.log"


def clean_storage():
    os.makedirs(LOGS_DIR, exist_ok=True)
    for name in os.listdir(STORAGE_DIR):
        path = os.path.join(STORAGE_DIR, name)
        if name == "logs":
            for child in os.listdir(path):
                child_path = os.path.join(path, child)
                if os.path.isdir(child_path):
                    shutil.rmtree(child_path)
                else:
                    os.remove(child_path)
        elif os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
    for path in (STATUS_FILE, OUTBOX):
        if os.path.exists(path):
            os.remove(path)


def write_random_file(path, size):
    digest = hashlib.sha256()
    remaining = size
    with open(path, "wb") as f:
        while remaining:
            chunk = os.urandom(min(1024 * 1024, remaining))
            f.write(chunk)
            digest.update(chunk)
            remaining -= len(chunk)
    return digest.hexdigest()


def write_zero_file(path, size):
    digest = hashlib.sha256()
    chunk = b"\0" * (1024 * 1024)
    remaining = size
    with open(path, "wb") as f:
        while remaining:
            data = chunk[:min(len(chunk), remaining)]
            f.write(data)
            digest.update(data)
            remaining -= len(data)
    return digest.hexdigest()


def gzip_hash(path):
    digest = hashlib.sha256()
    with gzip.open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def run_daemon():
    result = subprocess.run(["/home/user/edge_daemon.sh"], capture_output=True, text=True)
    assert result.returncode == 0, f"edge_daemon.sh failed with output: {result.stderr}"


def usage_candidates_mb():
    values = []
    for extra in ([], ["--apparent-size"]):
        output = subprocess.check_output(
            ["du", "-s", "-B1", *extra, STORAGE_DIR], text=True
        )
        values.append(int(output.split()[0]) / (1024 * 1024))

    candidates = set()
    for value in values:
        candidates.add(math.floor(value))
        candidates.add(math.ceil(value))
        candidates.add(math.floor(value + 0.5))
    return candidates


def test_scripts_exist_and_executable():
    check_storage = "/home/user/check_storage.sh"
    assert os.path.isfile(check_storage), f"{check_storage} is missing"
    assert os.access(check_storage, os.X_OK), f"{check_storage} is not executable"

    edge_daemon = "/home/user/edge_daemon.sh"
    assert os.path.isfile(edge_daemon), f"{edge_daemon} is missing"
    assert os.access(edge_daemon, os.X_OK), f"{edge_daemon} is not executable"


def test_logrotate_conf_exists_and_contains_rules():
    conf_path = "/home/user/iot_logrotate.conf"
    assert os.path.isfile(conf_path), f"{conf_path} is missing"

    with open(conf_path, "r") as f:
        content = f.read().lower()

    assert "5m" in content or "5120k" in content, "Size 5M rule not found in logrotate config"
    assert "rotate 2" in content, "rotate 2 rule not found in logrotate config"
    assert "compress" in content, "compress rule not found in logrotate config"
    assert "missingok" in content, "missingok rule not found in logrotate config"
    assert "nomail" in content, "nomail rule not found in logrotate config"

    uncommented = "\n".join(line.split("#", 1)[0] for line in content.splitlines())
    block_match = re.search(
        r'(?m)^\s*(?:"/home/user/edge_storage/logs/\*\.log"|/home/user/edge_storage/logs/\*\.log)\s*\{',
        uncommented,
    )
    assert block_match, "No active logrotate block manages /home/user/edge_storage/logs/*.log"
    start = block_match.end()
    end = uncommented.find("}", start)
    assert end != -1, "The logrotate block is not closed"
    block = uncommented[start:end]

    assert re.search(r"(?mi)^\s*size\s+(?:5m|5120k)\s*$", block), "The managed block lacks size 5M"
    assert re.search(r"(?mi)^\s*rotate\s+2\s*$", block), "The managed block lacks rotate 2"
    assert re.search(r"(?mi)^\s*compress\s*$", block), "The managed block lacks compress"
    assert re.search(r"(?mi)^\s*missingok\s*$", block), "The managed block lacks missingok"
    assert re.search(r"(?mi)^\s*nomail\s*$", block), "The managed block lacks nomail"


def test_execution_and_results():
    clean_storage()

    subprocess.run(["dd", "if=/dev/urandom", f"of={LOGS_DIR}/sensor_alpha.log", "bs=1M", "count=6"], check=True, stderr=subprocess.DEVNULL)
    subprocess.run(["dd", "if=/dev/urandom", f"of={LOGS_DIR}/sensor_beta.log", "bs=1M", "count=16"], check=True, stderr=subprocess.DEVNULL)

    run_daemon()

    assert os.path.exists(f"{LOGS_DIR}/sensor_alpha.log.1.gz"), "sensor_alpha.log was not rotated and compressed"
    assert os.path.exists(f"{LOGS_DIR}/sensor_beta.log.1.gz"), "sensor_beta.log was not rotated and compressed"
    assert os.path.exists(OUTBOX), "mail_outbox.log was not created; check_storage.sh failed to send mail."

    with open(OUTBOX, "r") as f:
        mail_content = f.read()

    assert "Subject: ALERT: IoT Storage High" in mail_content, "Missing or incorrect email subject in mail outbox."
    match = re.search(r"Current usage:\s*(\d+)\s*MB", mail_content)
    assert match is not None, "Missing or incorrectly formatted 'Current usage: X MB' string in email body."
    size_mb = int(match.group(1))
    assert size_mb in [21, 22, 23], f"Reported size {size_mb} MB is incorrect (expected ~22 MB)."


def test_dynamic_rotation_threshold_contents_and_retention():
    clean_storage()
    token = uuid.uuid4().hex
    large = os.path.join(LOGS_DIR, f"large_{token}.log")
    small = os.path.join(LOGS_DIR, f"small_{token}.log")
    large_hash = write_random_file(large, 5 * 1024 * 1024 + 32768)
    small_hash = write_random_file(small, 4 * 1024 * 1024 + 32768)

    run_daemon()

    large_backup = large + ".1.gz"
    assert os.path.isfile(large_backup), "A dynamically named log above 5M was not rotated and compressed"
    assert gzip_hash(large_backup) == large_hash, "The compressed backup does not contain the original log"
    assert os.path.isfile(small), "A log below 5M was incorrectly rotated"
    assert not os.path.exists(small + ".1.gz"), "A log below 5M was incorrectly backed up"
    assert hashlib.sha256(open(small, "rb").read()).hexdigest() == small_hash

    clean_storage()
    base = os.path.join(LOGS_DIR, f"retention_{uuid.uuid4().hex}.log")
    hashes = []
    for _ in range(3):
        hashes.append(write_random_file(base, 5 * 1024 * 1024 + 65536))
        run_daemon()

    backups = sorted(
        name for name in os.listdir(LOGS_DIR)
        if name.startswith(os.path.basename(base) + ".")
    )
    assert backups == [os.path.basename(base) + ".1.gz", os.path.basename(base) + ".2.gz"], \
        f"Expected exactly two compressed backups, found: {backups}"
    assert gzip_hash(base + ".1.gz") == hashes[-1]
    assert gzip_hash(base + ".2.gz") == hashes[-2]


def test_storage_monitor_below_and_above_threshold_with_derived_usage():
    clean_storage()
    low_size = (9 + int(uuid.uuid4().hex[:2], 16) % 7) * 1024 * 1024 + 131072
    write_random_file(os.path.join(STORAGE_DIR, f"low_{uuid.uuid4().hex}.bin"), low_size)
    low_result = subprocess.run(["/home/user/check_storage.sh"], capture_output=True, text=True)
    assert low_result.returncode == 0, low_result.stderr
    assert not os.path.exists(OUTBOX) or os.path.getsize(OUTBOX) == 0, \
        "An alert was sent while storage usage was below 20 MB"

    clean_storage()
    high_size = (22 + int(uuid.uuid4().hex[:2], 16) % 6) * 1024 * 1024 + 393216
    write_random_file(os.path.join(STORAGE_DIR, f"high_{uuid.uuid4().hex}.bin"), high_size)
    expected = usage_candidates_mb()
    assert min(expected) > 20

    high_result = subprocess.run(["/home/user/check_storage.sh"], capture_output=True, text=True)
    assert high_result.returncode == 0, high_result.stderr
    assert os.path.isfile(OUTBOX), "No alert was sent while storage usage was above 20 MB"
    with open(OUTBOX) as f:
        mail = f.read()
    assert re.search(r"(?m)^Subject: ALERT: IoT Storage High$", mail), "The exact alert subject header is missing"
    match = re.search(r"(?m)^Current usage: (\d+) MB$", mail)
    assert match, "The exact Current usage: X MB body line is missing"
    reported = int(match.group(1))
    assert reported in expected, f"Reported {reported} MB, but measured usage permits {sorted(expected)}"


def test_daemon_rotates_before_monitoring():
    clean_storage()
    path = os.path.join(LOGS_DIR, f"order_{uuid.uuid4().hex}.log")
    original_hash = write_zero_file(path, 22 * 1024 * 1024)
    run_daemon()

    backup = path + ".1.gz"
    assert os.path.isfile(backup), "Daemon did not rotate the oversized log"
    assert gzip_hash(backup) == original_hash, "Rotated data was not preserved"
    assert not os.path.exists(OUTBOX) or os.path.getsize(OUTBOX) == 0, \
        "Monitoring ran before rotation reduced the compressible storage usage"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
