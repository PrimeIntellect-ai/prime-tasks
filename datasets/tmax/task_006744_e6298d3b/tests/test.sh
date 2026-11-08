#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import tarfile
import time
import uuid

import pytest

WATCHER = "/home/user/watcher.py"


def watcher_pids():
    """Return live processes whose command line executes /home/user/watcher.py."""
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        procdir = os.path.join("/proc", entry)
        try:
            with open(os.path.join(procdir, "cmdline"), "rb") as f:
                args = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
            cwd = os.readlink(os.path.join(procdir, "cwd"))
        except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
            continue

        for arg in args:
            if not arg.endswith("watcher.py"):
                continue
            candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
            if os.path.realpath(candidate) == WATCHER:
                found.append(int(entry))
                break
    return found


def normalized_file_members(tar_path):
    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            return [m.name.lstrip("/") for m in tar.getmembers() if m.isfile()]
    except Exception as exc:
        pytest.fail(f"Could not read tar file {tar_path}: {exc}")


def test_archive_exists():
    """Verify that the required demonstration archive was created."""
    tar_path = "/home/user/archives/test_run.tar.gz"
    assert os.path.exists(tar_path), f"Archive {tar_path} was not found."
    assert os.path.isfile(tar_path), f"{tar_path} is not a file."


def test_trigger_file_deleted():
    """Verify that the required demonstration trigger was deleted."""
    csv_path = "/home/user/requests/test_run.csv"
    assert not os.path.exists(csv_path), f"Trigger file {csv_path} was not deleted."


def test_archive_contents():
    """Verify the original demonstration archive contents."""
    tar_path = "/home/user/archives/test_run.tar.gz"
    assert os.path.exists(tar_path), f"Archive {tar_path} was not found."

    expected_files = {
        "home/user/data/logs/medium.log",
        "home/user/data/logs/large.log",
        "home/user/data/backups/new.bak",
    }
    unexpected_files = {
        "home/user/data/logs/small.log",
        "home/user/data/backups/old.bak",
    }
    members = normalized_file_members(tar_path)

    for expected in expected_files:
        assert expected in members, f"Expected file {expected} is missing from the archive."
    for unexpected in unexpected_files:
        assert unexpected not in members, f"Unexpected file {unexpected} was found in the archive."


def test_watcher_is_live_and_processes_new_request():
    assert os.path.isfile(WATCHER), f"Watcher script {WATCHER} does not exist or is not a file."
    assert watcher_pids(), f"No running process executing {WATCHER} was found."

    token = uuid.uuid4().hex
    root = f"/home/user/verifier_data_{token}"
    first = os.path.join(root, "first")
    second = os.path.join(root, "second")
    nested = os.path.join(first, "nested")
    os.makedirs(nested)
    os.makedirs(second)
    os.chmod(root, 0o777)
    os.chmod(first, 0o777)
    os.chmod(second, 0o777)
    os.chmod(nested, 0o777)

    threshold1 = 3000 + secrets.randbelow(2000)
    threshold2 = 9000 + secrets.randbelow(2000)
    specifications = [
        (os.path.join(first, f"below_{token}.bin"), threshold1 - 1, False),
        (os.path.join(first, f"boundary_{token}.bin"), threshold1, False),
        (os.path.join(nested, f"above_{token}.bin"), threshold1 + 137, True),
        (os.path.join(second, f"below_{token}.bin"), threshold2 - 23, False),
        (os.path.join(second, f"boundary_{token}.bin"), threshold2, False),
        (os.path.join(second, f"above_{token}.bin"), threshold2 + 211, True),
    ]
    expected = set()
    for path, size, should_match in specifications:
        with open(path, "wb") as f:
            f.write(os.urandom(size))
        os.chmod(path, 0o666)
        if should_match:
            expected.add(path.lstrip("/"))

    request_name = f"verify_{token}.csv"
    request_path = os.path.join("/home/user/requests", request_name)
    archive_path = os.path.join("/home/user/archives", f"verify_{token}.tar.gz")
    assert not os.path.exists(archive_path)
    with open(request_path, "w", newline="") as f:
        f.write(f"{first},{threshold1}\n")
        f.write(f"{second},{threshold2}\n")

    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if os.path.isfile(archive_path) and not os.path.exists(request_path):
            break
        time.sleep(0.25)

    assert os.path.isfile(archive_path), "The running watcher did not create an archive for a new CSV request."
    assert not os.path.exists(request_path), "The watcher did not delete the newly processed CSV request."
    assert watcher_pids(), "The watcher stopped instead of continuing to monitor for requests."

    members = normalized_file_members(archive_path)
    assert set(members) == expected, (
        f"Archive for the new request had incorrect contents. Expected {sorted(expected)}, "
        f"got {sorted(set(members))}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
