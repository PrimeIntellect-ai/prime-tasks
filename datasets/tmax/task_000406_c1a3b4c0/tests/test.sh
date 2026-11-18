#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_tracker.py
import fcntl
import gzip
import io
import json
import os
import subprocess
import tarfile
import time
import uuid

TRACKER = "/home/user/tracker.go"
LOG = "/home/user/backup_events.log"
STATE = "/home/user/state.json"
BACKUPS = "/home/user/backups"


def make_tar(path, name, data):
    with tarfile.open(path, "w:gz") as tf:
        info = tarfile.TarInfo(name)
        info.size = len(data)
        tf.addfile(info, io.BytesIO(data))


def run_checked(command, timeout=30):
    result = subprocess.run(command, text=True, capture_output=True, timeout=timeout)
    assert result.returncode == 0, (
        f"Command {' '.join(command)} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_state():
    assert os.path.exists(STATE), f"State file {STATE} does not exist"
    with open(STATE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"{STATE} does not contain valid JSON: {exc}")
    assert "valid_backups" in data, "Key 'valid_backups' is missing in state.json"
    return data


def test_tracker_end_to_end():
    assert os.path.isfile(TRACKER), f"Source file {TRACKER} does not exist"
    with open(TRACKER, "r") as f:
        content = f.read()

    # Preserve the original implementation requirements.
    assert "syscall.Flock" in content, (
        "tracker.go is missing 'syscall.Flock'. You must use syscall.Flock for exclusive file locking."
    )
    assert "os.Rename" in content or "syscall.Rename" in content, (
        "tracker.go is missing an atomic rename operation for updating state.json."
    )

    os.makedirs(BACKUPS, exist_ok=True)

    # Recreate the documented inputs so a pre-written state file cannot pass.
    cfg1 = os.path.join(BACKUPS, "cfg_01.tar.gz")
    cfg2 = os.path.join(BACKUPS, "cfg_02.tar.gz")
    cfg3 = os.path.join(BACKUPS, "cfg_03.tar.gz")
    cfg4 = os.path.join(BACKUPS, "cfg_04.tar.gz")
    make_tar(cfg1, "cfg1/config.txt", b"data\n")
    make_tar(cfg2, "cfg2/config.txt", b"data2\n")
    with open(cfg3, "wb") as f:
        f.write(b"This is not a tarball\n")
    make_tar(cfg4, "cfg4/config.txt", b"data4\n")

    with open(LOG, "w") as f:
        f.write(f"""[Event ID: 101]
Type: ConfigBackup
File: {cfg1}
Status: Pending

[Event ID: 102]
Type: ConfigBackup
File: {cfg2}
Status: Processed

[Event ID: 103]
Type: ConfigBackup
File: {cfg3}
Status: Pending

[Event ID: 104]
Type: ConfigBackup
File: {cfg4}
Status: Pending
""")
    with open(STATE, "w") as f:
        json.dump({"valid_backups": []}, f)

    # Execute the artifact exactly as requested.
    run_checked(["go", "run", TRACKER])
    expected_backups = [cfg1, cfg4]
    actual_backups = read_state()["valid_backups"]
    assert actual_backups == expected_backups, (
        f"Expected valid_backups to be {expected_backups}, but got {actual_backups}. "
        "Ensure only Pending and valid tar.gz archives are included, in the correct order."
    )

    # Build once for a second randomized behavioral test, including lock blocking.
    binary = "/tmp/tracker-under-test"
    run_checked(["go", "build", "-o", binary, TRACKER])

    case_dir = os.path.join(BACKUPS, "case_" + uuid.uuid4().hex)
    os.makedirs(case_dir)
    valid_a = os.path.join(case_dir, "first.tar.gz")
    valid_b = os.path.join(case_dir, "second.tar.gz")
    processed = os.path.join(case_dir, "processed.tar.gz")
    bad_gzip_tar = os.path.join(case_dir, "bad_payload.tar.gz")
    truncated_tar = os.path.join(case_dir, "truncated.tar.gz")
    missing = os.path.join(case_dir, "missing.tar.gz")

    make_tar(valid_a, "a/settings.ini", os.urandom(37))
    make_tar(valid_b, "b/config.json", os.urandom(91))
    make_tar(processed, "ignored/file", b"valid but processed")
    with open(bad_gzip_tar, "wb") as f:
        f.write(gzip.compress(b"this is gzip data but not a tar archive"))

    raw_tar = io.BytesIO()
    with tarfile.open(fileobj=raw_tar, mode="w") as tf:
        payload = os.urandom(4096)
        info = tarfile.TarInfo("partial/data.bin")
        info.size = len(payload)
        tf.addfile(info, io.BytesIO(payload))
    with open(truncated_tar, "wb") as f:
        f.write(gzip.compress(raw_tar.getvalue()[:1000]))

    with open(LOG, "w") as f:
        f.write(f"""[Event ID: 901]
Type: ConfigBackup
File: {valid_b}
Status: Pending

[Event ID: 902]
Type: ConfigBackup
File: {processed}
Status: Processed

[Event ID: 903]
Type: ConfigBackup
File: {bad_gzip_tar}
Status: Pending

[Event ID: 904]
Type: ConfigBackup
File: {missing}
Status: Pending

[Event ID: 905]
Type: ConfigBackup
File: {valid_a}
Status: Pending

[Event ID: 906]
Type: ConfigBackup
File: {truncated_tar}
Status: Pending
""")

    existing = "/already/present/backup.tar.gz"
    with open(STATE, "w") as f:
        json.dump({"valid_backups": [existing]}, f)

    # Hold the same advisory lock the program is required to acquire. A correct
    # implementation must remain blocked until this lock is released.
    lock_file = open(STATE, "r+")
    old_inode = os.fstat(lock_file.fileno()).st_ino
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    proc = subprocess.Popen([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        time.sleep(0.75)
        assert proc.poll() is None, "tracker exited while state.json was exclusively locked"
        assert read_state()["valid_backups"] == [existing], "tracker changed state while the lock was held"
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        stdout, stderr = proc.communicate(timeout=15)
        assert proc.returncode == 0, (
            f"tracker failed with exit code {proc.returncode}.\nstdout:\n{stdout}\nstderr:\n{stderr}"
        )
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        lock_file.close()

    expected_dynamic = [existing, valid_b, valid_a]
    actual_dynamic = read_state()["valid_backups"]
    assert actual_dynamic == expected_dynamic, (
        f"Expected randomized valid_backups to be {expected_dynamic}, got {actual_dynamic}"
    )

    # Renaming a same-directory temporary file over state.json replaces its inode.
    assert os.stat(STATE).st_ino != old_inode, (
        "state.json was not replaced using the required atomic rename pattern"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_tracker.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
