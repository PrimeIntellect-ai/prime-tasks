#!/bin/bash
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_corrupted_log():
    log_path = "/home/user/repo/corrupted.log"
    assert os.path.exists(log_path), f"File {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read().strip().splitlines()
    assert "bad_data.tar.gz" in content, f"Expected 'bad_data.tar.gz' in {log_path}, got {content}"

def test_symlinks_created():
    symlink1 = "/home/user/repo/database/sqldb/1.0.0/payload.tar.gz"
    target1 = "/home/user/incoming/db_v1.tar.gz"

    symlink2 = "/home/user/repo/web/server/2.1.4/payload.tar.gz"
    target2 = "/home/user/incoming/web_v2.tar.gz"

    assert os.path.islink(symlink1), f"{symlink1} is not a symlink."
    assert os.readlink(symlink1) == target1, f"{symlink1} does not point to {target1}."

    assert os.path.islink(symlink2), f"{symlink2} is not a symlink."
    assert os.readlink(symlink2) == target2, f"{symlink2} does not point to {target2}."

def test_final_layout_txt():
    layout_path = "/home/user/repo/final_layout.txt"
    assert os.path.exists(layout_path), f"File {layout_path} does not exist."
    with open(layout_path, "r") as f:
        content = f.read().strip().splitlines()

    expected = [
        "/home/user/repo/database/sqldb/1.0.0/payload.tar.gz",
        "/home/user/repo/web/server/2.1.4/payload.tar.gz"
    ]
    assert content == expected, f"Expected {layout_path} to contain exactly {expected}, got {content}"
TEST_EOF

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    exit 0
fi

cat << 'BEHAVIOR_EOF' > /tmp/test_curator_behavior.py
import io
import json
import os
import py_compile
import shutil
import signal
import stat
import subprocess
import tarfile
import time
import uuid

SCRIPT = "/home/user/curator.py"
INCOMING = "/home/user/incoming"
REPO = "/home/user/repo"

assert os.path.exists(SCRIPT), f"Missing required script: {SCRIPT}"
assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a real Python file"
assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file"
py_compile.compile(SCRIPT, doraise=True)

# Stop any curator left running by the agent before creating a clean behavioral test.
for entry in os.listdir("/proc"):
    if not entry.isdigit():
        continue
    try:
        raw = open(f"/proc/{entry}/cmdline", "rb").read()
        argv = [x.decode(errors="ignore") for x in raw.split(b"\0") if x]
        if SCRIPT in argv:
            os.kill(int(entry), signal.SIGTERM)
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        pass
time.sleep(0.3)

shutil.rmtree(INCOMING, ignore_errors=True)
shutil.rmtree(REPO, ignore_errors=True)
os.makedirs(INCOMING)
os.makedirs(REPO)

token = uuid.uuid4().hex[:10]
items = [
    (f"cat_{token}_a", f"name_{token}_a", f"3.{len(token)}.1", f"artifact_{token}_a.tar.gz"),
    (f"cat_{token}_b", f"name_{token}_b", f"7.{len(token)}.9", f"artifact_{token}_b.tar.gz"),
]
bad_name = f"corrupt_{token}.tar.gz"

def make_archive(category, name, version, filename):
    path = os.path.join(INCOMING, filename)
    metadata = json.dumps({"category": category, "name": name, "version": version}).encode()
    payload = ("dynamic payload " + token).encode()
    with tarfile.open(path, "w:gz") as archive:
        info = tarfile.TarInfo("meta.json")
        info.size = len(metadata)
        archive.addfile(info, io.BytesIO(metadata))
        info = tarfile.TarInfo("payload.bin")
        info.size = len(payload)
        archive.addfile(info, io.BytesIO(payload))
    return path

def expected_link(item):
    category, name, version, _ = item
    return os.path.join(REPO, category, name, version, "payload.tar.gz")

def wait_for(predicate, timeout=7):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.15)
    return False

proc = subprocess.Popen(
    ["python3", SCRIPT],
    cwd="/tmp",
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
try:
    time.sleep(1.1)
    assert proc.poll() is None, "curator.py did not remain running to monitor continuously"

    first_path = make_archive(*items[0])
    first_link = expected_link(items[0])
    assert wait_for(lambda: os.path.islink(first_link)), "First dynamically named archive was not processed"
    assert os.readlink(first_link) == first_path, "First symlink does not target the absolute incoming path"
    assert proc.poll() is None, "curator.py stopped after processing one archive"

    # Drop more files after the first result to verify continued monitoring.
    time.sleep(0.5)
    second_path = make_archive(*items[1])
    with open(os.path.join(INCOMING, bad_name), "wb") as bad:
        bad.write(b"not a gzip or tar archive: " + token.encode())

    second_link = expected_link(items[1])
    log_path = os.path.join(REPO, "corrupted.log")
    assert wait_for(lambda: os.path.islink(second_link)), "Later dynamically named archive was not processed"
    assert os.readlink(second_link) == second_path, "Second symlink does not target the absolute incoming path"
    assert wait_for(lambda: os.path.exists(log_path) and bad_name in open(log_path).read().splitlines()), \
        "Dynamically named corrupt archive was not logged"
    assert proc.poll() is None, "curator.py stopped instead of continuing to monitor"

    # A processed file must not be handled again on every polling pass.
    os.unlink(first_link)
    time.sleep(2.5)
    assert not os.path.lexists(first_link), "A previously processed valid file was processed a second time"
    with open(log_path) as log:
        lines = log.read().splitlines()
    assert lines.count(bad_name) == 1, "The same corrupt file was logged more than once"

    for root, dirs, files in os.walk(REPO):
        for filename in files:
            path = os.path.join(root, filename)
            if os.path.islink(path):
                assert os.readlink(path) != os.path.join(INCOMING, bad_name), \
                    "Corrupt archive was routed into the repository"
finally:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=3)
BEHAVIOR_EOF

if ! python3 /tmp/test_curator_behavior.py 2>&1; then
    exit 0
fi

reward=1
exit 0
