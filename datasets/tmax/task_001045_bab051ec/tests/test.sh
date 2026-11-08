#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import atexit
import collections
import json
import os
import re
import secrets
import signal
import socket
import stat
import subprocess
import time

import requests

BINARY = "/home/user/log_processor"
LOG_FILE = "/home/user/processed_logs.csv"
PORTS = (9000, 9001)
_started_process = None


def listening_inodes(ports):
    wanted = {f"{port:04X}" for port in ports}
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    if fields[1].rsplit(":", 1)[-1].upper() in wanted:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def owners_of_inodes(inodes):
    owners = set()
    if not inodes:
        return owners
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(name))
                    break
        except OSError:
            continue
    return owners


def stop_existing_services():
    # Stop the supplied generator first so it cannot reconnect during testing.
    try:
        output = subprocess.check_output(["pgrep", "-f", "/app/generator.py"], text=True)
        for item in output.split():
            pid = int(item)
            if pid != os.getpid():
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
    except subprocess.CalledProcessError:
        pass

    owners = owners_of_inodes(listening_inodes(PORTS))
    for pid in owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and owners_of_inodes(listening_inodes(PORTS)):
        time.sleep(0.05)
    for pid in owners_of_inodes(listening_inodes(PORTS)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.15)


def cleanup_processor():
    global _started_process
    owners = owners_of_inodes(listening_inodes(PORTS))
    for pid in owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if _started_process is not None and _started_process.poll() is None:
        try:
            _started_process.terminate()
            _started_process.wait(timeout=2)
        except Exception:
            try:
                _started_process.kill()
            except Exception:
                pass


atexit.register(cleanup_processor)


def wait_for_services():
    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 9000), timeout=0.3):
                pass
            response = requests.get("http://127.0.0.1:9001/stats", timeout=0.5)
            if response.status_code == 200:
                return
        except Exception as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"Processor did not open both required services: {last_error}")


def get_stats():
    try:
        response = requests.get("http://127.0.0.1:9001/stats", timeout=2)
    except Exception as exc:
        raise AssertionError(f"Failed to connect to HTTP 9001: {exc}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type: application/json"
    try:
        data = response.json()
    except Exception:
        raise AssertionError(f"Failed to parse JSON response: {response.text}")
    assert "unique" in data and "duplicates" in data, "JSON response missing required keys"
    assert set(data) == {"unique", "duplicates"}, "JSON response contains keys other than unique and duplicates"
    for key in ("unique", "duplicates"):
        assert isinstance(data[key], int) and not isinstance(data[key], bool), f"{key} must be an integer"
        assert data[key] >= 0, f"{key} must be non-negative"
    return data


def send_records(records, fragmented=False):
    payload = "".join(",".join(row) + "\n" for row in records).encode()
    try:
        with socket.create_connection(("127.0.0.1", 9000), timeout=2) as sock:
            if fragmented:
                positions = [1, 7, 19, 43, 91]
                start = 0
                for end in positions:
                    if start < len(payload):
                        sock.sendall(payload[start:min(end, len(payload))])
                        start = min(end, len(payload))
                if start < len(payload):
                    sock.sendall(payload[start:])
            else:
                sock.sendall(payload)
    except Exception as exc:
        raise AssertionError(f"Failed to connect and send data to TCP 9000: {exc}")


def masked(row):
    output = list(row)
    output[2] = output[2].rsplit(".", 1)[0] + ".XXX"
    output[3] = "***@" + output[3].split("@", 1)[1]
    return ",".join(output)


def test_complete_task():
    global _started_process

    stop_existing_services()

    assert os.path.exists(BINARY), f"Compiled processor {BINARY} does not exist"
    metadata = os.lstat(BINARY)
    assert stat.S_ISREG(metadata.st_mode), "log_processor must be a regular compiled executable"
    assert os.access(BINARY, os.X_OK), "log_processor is not executable"
    with open(BINARY, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "log_processor is not an ELF compiled binary"

    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "w"):
        pass

    _started_process = subprocess.Popen(
        [BINARY], cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    wait_for_services()

    socket_owners = owners_of_inodes(listening_inodes(PORTS))
    assert socket_owners, "Could not identify the process listening on the required ports"
    expected_exe = os.path.realpath(BINARY)
    owner_executables = set()
    for pid in socket_owners:
        try:
            owner_executables.add(os.path.realpath(os.readlink(f"/proc/{pid}/exe")))
        except OSError:
            pass
    assert owner_executables == {expected_exe}, "Ports 9000 and 9001 are not served by /home/user/log_processor"

    initial = get_stats()
    unchanged = get_stats()
    assert unchanged == initial, "Stats changed merely because /stats was requested"

    token = secrets.token_hex(10)
    original_unique = [
        ("1690000000", "req_test_100", "10.0.0.1", "test@domain.com", "login", "1"),
        ("1690000002", "req_test_101", "10.0.0.2", "admin@domain.com", "logout", "0"),
    ]
    random_unique = []
    for i in range(6):
        random_unique.append((
            str(1800000000 + i),
            f"audit_{token}_{i}",
            f"172.{20 + i}.{40 + i}.{70 + i}",
            f"private-{token}-{i}@host{i}.example.net",
            f"event_{i}",
            str(i * 17 - 3),
        ))

    first_batch = [original_unique[0],
                   ("1690000001", "req_test_100", "10.0.0.99", "other@evil.invalid", "changed", "999"),
                   original_unique[1]] + random_unique
    second_batch = [
        ("1900000001", random_unique[0][1], "8.8.8.8", "leak@wrong.invalid", "retry", "500"),
        ("1900000002", random_unique[2][1], "9.9.9.9", "leak2@wrong.invalid", "retry", "501"),
        ("1900000003", random_unique[5][1], "7.7.7.7", "leak3@wrong.invalid", "retry", "502"),
    ]
    unique_rows = original_unique + random_unique
    duplicate_count = 1 + len(second_batch)

    send_records(first_batch, fragmented=True)
    send_records(second_batch, fragmented=False)

    expected_lines = collections.Counter(masked(row) for row in unique_rows)
    deadline = time.time() + 6
    actual_lines = []
    while time.time() < deadline:
        try:
            with open(LOG_FILE) as f:
                actual_lines = [line.rstrip("\n") for line in f]
        except FileNotFoundError:
            actual_lines = []
        if len(actual_lines) >= len(unique_rows):
            break
        time.sleep(0.1)

    final = get_stats()
    assert final["unique"] >= initial["unique"] + 2, f"Expected at least {initial['unique'] + 2} unique records, got {final['unique']}"
    assert final["duplicates"] >= initial["duplicates"] + 1, f"Expected at least {initial['duplicates'] + 1} duplicate records, got {final['duplicates']}"
    assert final["unique"] == initial["unique"] + len(unique_rows), "Unique counter did not increase by the exact number of unique record IDs"
    assert final["duplicates"] == initial["duplicates"] + duplicate_count, "Duplicate counter did not increase by the exact number of repeated record IDs"
    assert get_stats() == final, "Stats changed merely because /stats was requested"

    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} does not exist"
    assert collections.Counter(actual_lines) == expected_lines, "The log must contain each complete transformed unique row exactly once and no other rows"

    content = "\n".join(actual_lines)
    assert "10.0.0.XXX" in content, "IP address not masked correctly (expected 10.0.0.XXX)"
    assert "***@domain.com" in content, "Email not masked correctly (expected ***@domain.com)"
    assert "10.0.0.1" not in content, "Unmasked IP address found in logs"
    assert "test@domain.com" not in content, "Unmasked email found in logs"
    for row in unique_rows:
        assert row[2] not in content, f"Unmasked IP address found in logs: {row[2]}"
        assert row[3] not in content, f"Unmasked email found in logs: {row[3]}"
    for duplicate in [first_batch[1]] + second_batch:
        assert masked(duplicate) not in actual_lines, "A duplicate record's replacement data was written"

    cleanup_processor()

    script_file = "/home/user/rotate.sh"
    archive_dir = "/home/user/archive"
    assert os.path.exists(script_file), f"Rotation script {script_file} does not exist"
    assert os.path.isdir(archive_dir), f"Archive directory {archive_dir} does not exist"

    marker = f"dummy_data_{token}\n"
    with open(LOG_FILE, "a") as f:
        f.write(marker)
    initial_size = os.path.getsize(LOG_FILE)
    assert initial_size > 0, "Log file is empty before rotation"
    inode_before = os.stat(LOG_FILE).st_ino

    # Avoid an archive-name collision with a pre-existing file from the same second.
    while os.path.exists(os.path.join(archive_dir, f"log_{int(time.time())}.csv")):
        time.sleep(1.05)
    archives_before = set(os.listdir(archive_dir))
    subprocess.run(["bash", script_file], check=True)

    assert os.path.getsize(LOG_FILE) == 0, "Log file was not truncated after rotation"
    assert os.stat(LOG_FILE).st_ino == inode_before, "Rotation deleted/replaced the original log inode instead of truncating it"
    archives_after = set(os.listdir(archive_dir))
    new_archives = archives_after - archives_before
    assert len(new_archives) >= 1, "No new archive file was created in the archive directory"
    assert any(marker.strip() in open(os.path.join(archive_dir, name), errors="replace").read()
               for name in new_archives), "The new archive did not contain the data copied from processed_logs.csv"

    try:
        crontab = subprocess.check_output(["crontab", "-u", "user", "-l"], stderr=subprocess.STDOUT).decode()
    except subprocess.CalledProcessError:
        raise AssertionError("Failed to read crontab for user")
    assert "/home/user/rotate.sh" in crontab, "Rotation script not found in crontab"
    active_lines = [line for line in crontab.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    schedule = re.compile(r"^\s*\*\s+\*\s+\*\s+\*\s+\*\s+/home/user/rotate\.sh(?:\s|$)")
    assert any(schedule.search(line) for line in active_lines), "Crontab does not have the exact '* * * * *' schedule for rotate.sh"

    cron_running = False
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/comm") as f:
                if f.read().strip() == "cron":
                    cron_running = True
                    break
        except OSError:
            pass
    assert cron_running, "The cron service is not running"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
