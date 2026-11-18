#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import time
import uuid

BASE = "/home/user/watchdog"
SCRIPT = os.path.join(BASE, "daemon.sh")
PID_FILE = os.path.join(BASE, "daemon.pid")
LINKS = os.path.join(BASE, "links")
TARGETS = os.path.join(BASE, "targets")
LOG = os.path.join(BASE, "logs", "watch.log")
OLD_LOG = os.path.join(BASE, "logs", "watch.log.old")


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def stop_daemon():
    subprocess.run([SCRIPT, "stop"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, timeout=5)


def clean_runtime():
    stop_daemon()
    for path in (PID_FILE, LOG, OLD_LOG):
        if os.path.lexists(path):
            remove_path(path)
    for directory in (LINKS, TARGETS):
        for name in os.listdir(directory):
            remove_path(os.path.join(directory, name))


def start_daemon():
    result = subprocess.run([SCRIPT, "start"], stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True, timeout=5)
    assert result.returncode == 0, f"Failed to start daemon: {result.stderr}"
    deadline = time.time() + 2
    while time.time() < deadline and not os.path.isfile(PID_FILE):
        time.sleep(0.05)
    assert os.path.isfile(PID_FILE), "PID file was not created."
    with open(PID_FILE) as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), "PID file does not contain a valid numeric PID."
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, "The process specified in the PID file is not running."
    return pid


def assert_stopped(pid):
    assert not os.path.exists(PID_FILE), "PID file was not removed after stop."
    deadline = time.time() + 2
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except OSError:
            return
        time.sleep(0.05)
    try:
        os.kill(pid, 0)
        process_running = True
    except OSError:
        process_running = False
    assert not process_running, "The background process was not terminated after stop."


def read_all_logs():
    result = ""
    for path in (OLD_LOG, LOG):
        if os.path.exists(path):
            with open(path) as f:
                result += f.read()
    return result


def wait_for(predicate, timeout, message):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    assert predicate(), message


def test_directory_structure():
    expected_dirs = [BASE, LINKS, os.path.join(BASE, "logs"), TARGETS]
    for directory in expected_dirs:
        assert os.path.isdir(directory), f"Directory {directory} is missing."


def test_daemon_script_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    mode = os.stat(SCRIPT).st_mode
    assert bool(mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable."


def test_original_daemon_behavior():
    clean_runtime()
    pid = start_daemon()
    try:
        time.sleep(1)

        broken_link = os.path.join(LINKS, "broken_link")
        os.symlink(os.path.join(TARGETS, "nonexistent"), broken_link)

        bad_target = os.path.join(TARGETS, "target1")
        with open(bad_target, "w") as f:
            f.write("bad")
        os.chmod(bad_target, 0o644)
        os.symlink(bad_target, os.path.join(LINKS, "bad_link"))

        good_target = os.path.join(TARGETS, "target2")
        with open(good_target, "w") as f:
            f.write("good")
        os.chmod(good_target, 0o600)
        os.symlink(good_target, os.path.join(LINKS, "good_link"))

        time.sleep(5)
        stop_daemon()
        assert_stopped(pid)

        contents = read_all_logs()
        assert "BROKEN: broken_link" in contents, "Missing expected log entry for broken link."
        assert "BADPERM: bad_link 644" in contents, "Missing expected log entry for bad permissions."
        assert "good_link" not in contents, "Log should not contain entries for valid links."
        assert os.path.exists(OLD_LOG), "Log rotation did not occur (watch.log.old is missing)."
    finally:
        stop_daemon()


def test_randomized_live_monitoring_and_rotation_threshold():
    clean_runtime()

    token = uuid.uuid4().hex
    marker = ("M" + token + "-")
    marker_bytes = (marker * ((100 // len(marker)) + 1)).encode()[:100]
    old_sentinel = ("OLD-" + uuid.uuid4().hex).encode()
    with open(LOG, "wb") as f:
        f.write(marker_bytes)
    with open(OLD_LOG, "wb") as f:
        f.write(old_sentinel)

    pid = start_daemon()
    try:
        # Exactly 100 bytes must not rotate, and an existing old log must remain untouched.
        time.sleep(2.4)
        assert os.path.getsize(LOG) == 100, "A 100-byte log must not be rotated."
        with open(OLD_LOG, "rb") as f:
            assert f.read() == old_sentinel, "watch.log.old changed before the log exceeded 100 bytes."

        broken_name = "dangling_" + uuid.uuid4().hex
        bad_name = "mode_" + uuid.uuid4().hex
        good_name = "secure_" + uuid.uuid4().hex
        regular_name = "regular_" + uuid.uuid4().hex
        directory_name = "directory_" + uuid.uuid4().hex

        os.symlink(os.path.join(TARGETS, "missing_" + uuid.uuid4().hex),
                   os.path.join(LINKS, broken_name))

        bad_target = os.path.join(TARGETS, "target_" + uuid.uuid4().hex)
        with open(bad_target, "w") as f:
            f.write("bad permissions")
        os.chmod(bad_target, 0o640)
        actual_mode = format(stat.S_IMODE(os.stat(bad_target).st_mode), "o")
        os.symlink(bad_target, os.path.join(LINKS, bad_name))

        good_target = os.path.join(TARGETS, "target_" + uuid.uuid4().hex)
        with open(good_target, "w") as f:
            f.write("secure")
        os.chmod(good_target, 0o600)
        os.symlink(good_target, os.path.join(LINKS, good_name))

        with open(os.path.join(LINKS, regular_name), "w") as f:
            f.write("not a symlink")
        os.mkdir(os.path.join(LINKS, directory_name))

        broken_entry = f"BROKEN: {broken_name}"
        bad_entry = f"BADPERM: {bad_name} {actual_mode}"

        def rotated_correctly():
            if not os.path.exists(OLD_LOG):
                return False
            with open(OLD_LOG, "rb") as f:
                data = f.read()
            text = data.decode(errors="replace")
            return marker_bytes in data and broken_entry in text and bad_entry in text

        wait_for(rotated_correctly, 4.5,
                 "The daemon did not derive randomized link results and rotate the oversized log.")
        assert os.path.getsize(OLD_LOG) > 100, "Rotation occurred before watch.log was greater than 100 bytes."
        with open(OLD_LOG, "rb") as f:
            rotated = f.read()
        assert old_sentinel not in rotated, "Rotation did not overwrite the existing watch.log.old."
        rotated_text = rotated.decode(errors="replace")
        assert good_name not in rotated_text, "A valid 600-permission symlink was logged."
        assert regular_name not in rotated_text, "A regular file in links/ was processed."
        assert directory_name not in rotated_text, "A directory in links/ was processed."

        # Change the live inputs after start and require a new, unpredictable result.
        os.unlink(os.path.join(LINKS, broken_name))
        os.unlink(os.path.join(LINKS, bad_name))
        live_name = "live_" + uuid.uuid4().hex
        live_target = os.path.join(TARGETS, "later_" + uuid.uuid4().hex)
        os.symlink(live_target, os.path.join(LINKS, live_name))
        live_entry = f"BROKEN: {live_name}"

        wait_for(lambda: os.path.exists(LOG) and live_entry in open(LOG).read(), 3.5,
                 "The running monitoring loop did not inspect a newly added symlink.")

        # Repairing that target to mode 600 must stop further entries.
        with open(live_target, "w") as f:
            f.write("now valid")
        os.chmod(live_target, 0o600)
        time.sleep(1.3)
        before = read_all_logs()
        time.sleep(2.2)
        after = read_all_logs()
        assert after == before, "The daemon kept logging a symlink after its target became valid with mode 600."

        stop_daemon()
        assert_stopped(pid)

        # Stopping must stop the monitor itself, not merely remove its advertised PID.
        stopped_snapshot = read_all_logs()
        post_stop_name = "poststop_" + uuid.uuid4().hex
        os.symlink(os.path.join(TARGETS, "absent_" + uuid.uuid4().hex),
                   os.path.join(LINKS, post_stop_name))
        time.sleep(1.6)
        assert read_all_logs() == stopped_snapshot, "Monitoring continued after stop."
    finally:
        stop_daemon()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
