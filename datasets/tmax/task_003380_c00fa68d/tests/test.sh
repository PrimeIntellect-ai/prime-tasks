#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import subprocess
import threading
import time
import uuid
import pytest

REPO = "/home/user/repo"
INCOMING = f"{REPO}/incoming"
OBJECTS = f"{REPO}/objects"
BY_NAME = f"{REPO}/by-name"
LATEST = f"{REPO}/latest.txt"


def checksum(data):
    return f"{sum(data) & 0xffffffff:08x}"


def wait_until(predicate, timeout=8.0, message="condition was not met"):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            if predicate():
                return
        except (FileNotFoundError, OSError) as exc:
            last_error = exc
        time.sleep(0.03)
    if last_error:
        raise AssertionError(f"{message}: {last_error}")
    raise AssertionError(message)


def assert_artifact(filename, data, timeout=8.0):
    expected = checksum(data)
    incoming = os.path.join(INCOMING, filename)
    object_path = os.path.join(OBJECTS, expected)
    link_path = os.path.join(BY_NAME, filename)

    with open(incoming, "wb") as f:
        f.write(data)

    def completed():
        if os.path.exists(incoming) or not os.path.isfile(object_path):
            return False
        if not os.path.islink(link_path):
            return False
        if os.readlink(link_path) != f"../objects/{expected}":
            return False
        with open(LATEST, "rb") as f:
            return f.read() == (expected + "\n").encode()

    wait_until(completed, timeout, f"curator did not completely process {filename}")
    assert not os.path.exists(incoming), f"Original file {incoming} was not deleted from incoming directory."
    assert os.path.exists(object_path), f"Object file {object_path} was not created. Expected checksum: {expected}"
    with open(object_path, "rb") as f:
        assert f.read() == data, "The contents of the object file do not match the original data."
    assert os.path.islink(link_path), f"Symlink {link_path} was not created."
    assert os.readlink(link_path) == f"../objects/{expected}"
    with open(LATEST, "r") as f:
        assert f.read() == expected + "\n"
    return expected


def kill_curator_processes():
    ancestors = set()
    pid = os.getpid()
    while pid > 1:
        ancestors.add(pid)
        try:
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().split()[3])
        except Exception:
            break

    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid in ancestors:
            continue
        try:
            raw = open(f"/proc/{pid}/cmdline", "rb").read()
            args = [x.decode(errors="ignore") for x in raw.split(b"\0") if x]
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        except Exception:
            continue
        names = [os.path.basename(x) for x in args]
        if exe.startswith("curator") or any(x.startswith("curator") for x in names) or any(x in ("/home/user/curator", "/tmp/curator_verified") for x in args):
            victims.append(pid)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.25)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def launch(path):
    proc = subprocess.Popen([path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(0.5)
    return proc


def dynamic_symbols(path):
    output = subprocess.check_output(["nm", "-D", path], stderr=subprocess.STDOUT, text=True)
    return output


def test_curator_binary_exists():
    """Verify that the curator binary was compiled and is executable."""
    binary_path = "/home/user/curator"
    assert os.path.exists(binary_path), f"The binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"The binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The curator executable is not a compiled ELF program."


def test_curator_running():
    """Verify that the curator daemon is running."""
    try:
        output = subprocess.check_output(["pgrep", "-f", "curator"]).decode()
        assert output.strip() != "", "The curator process is not running in the background."
    except subprocess.CalledProcessError:
        pytest.fail("The curator process is not running in the background.")


def test_curator_processing():
    """Retain the original fixed-file processing assertions."""
    test_filename = "pytest_artifact.bin"
    incoming_path = f"/home/user/repo/incoming/{test_filename}"
    data = os.urandom(512 * 1024)
    expected_checksum = checksum(data)

    with open(incoming_path, "wb") as f:
        f.write(data)
    time.sleep(3)

    assert not os.path.exists(incoming_path), f"Original file {incoming_path} was not deleted from incoming directory."
    object_path = f"/home/user/repo/objects/{expected_checksum}"
    assert os.path.exists(object_path), f"Object file {object_path} was not created. Expected checksum: {expected_checksum}"
    with open(object_path, "rb") as f:
        assert f.read() == data, "The contents of the object file do not match the original data."

    symlink_path = f"/home/user/repo/by-name/{test_filename}"
    assert os.path.islink(symlink_path), f"Symlink {symlink_path} was not created."
    target = os.readlink(symlink_path)
    expected_target = f"../objects/{expected_checksum}"
    assert target == expected_target, f"Symlink points to '{target}', expected '{expected_target}'."

    assert os.path.exists(LATEST), f"File {LATEST} does not exist."
    with open(LATEST, "r") as f:
        latest = f.read()
    assert latest == f"{expected_checksum}\n", f"latest.txt contains {repr(latest)}, expected {repr(expected_checksum + chr(10))}."


def test_source_and_full_behavior():
    source = "/home/user/curator.c"
    binary = "/home/user/curator"
    assert os.path.isfile(source), "The required /home/user/curator.c source file does not exist."
    assert not os.path.islink(source), "curator.c must be a submitted source file, not a symlink."
    with open(source, "r", errors="replace") as f:
        text = f.read()
    assert re.search(r"\binotify_(?:init|init1|add_watch)\b", text), "curator.c does not use inotify."
    assert "IN_CLOSE_WRITE" in text, "curator.c does not request IN_CLOSE_WRITE events."
    assert re.search(r"\bmmap\s*\(", text), "curator.c does not call mmap."
    assert re.search(r"\brename(?:at|at2)?\s*\(", text), "curator.c does not use rename for atomic publication."

    verified = "/tmp/curator_verified"
    subprocess.check_call(["gcc", "-O2", source, "-o", verified])
    for candidate in (binary, verified):
        symbols = dynamic_symbols(candidate)
        assert re.search(r"\binotify_init1?@|\binotify_init1?\b", symbols), f"{candidate} does not import inotify initialization."
        assert "inotify_add_watch" in symbols, f"{candidate} does not import inotify_add_watch."
        assert re.search(r"\bmmap(?:64)?@|\bmmap(?:64)?\b", symbols), f"{candidate} does not import mmap."
        assert re.search(r"\brename(?:at|at2)?@|\brename(?:at|at2)?\b", symbols), f"{candidate} does not import rename."
        assert re.search(r"\bsymlink(?:at)?@|\bsymlink(?:at)?\b", symbols), f"{candidate} does not import symlink creation."

    # Stop any pre-existing implementation and exercise the submitted executable itself.
    kill_curator_processes()
    home_proc = launch(binary)

    token = uuid.uuid4().hex
    seen = set()
    records = []
    for i in range(4):
        name = f"artifact_{token}_{i}.bin"
        data = os.urandom(12000 + i * 7001) + bytes([17 + i]) * (1000 + i * 113)
        value = checksum(data)
        while value in seen:
            data += os.urandom(1)
            value = checksum(data)
        seen.add(value)
        assert_artifact(name, data)
        records.append((name, data, value))

    # The same content under another unpredictable name must deduplicate to the same object.
    duplicate_name = f"duplicate_{uuid.uuid4().hex}.dat"
    duplicate_checksum = assert_artifact(duplicate_name, records[1][1])
    assert duplicate_checksum == records[1][2]
    assert os.readlink(os.path.join(BY_NAME, duplicate_name)) == f"../objects/{duplicate_checksum}"

    # Repeatedly replace one name while readers verify latest.txt and the symlink never
    # disappear or expose partial values. Combined with the rename import, this checks
    # the required atomic update path rather than only its final state.
    replace_name = f"replace_{uuid.uuid4().hex}.bin"
    payloads = []
    values = set()
    for i in range(9):
        data = os.urandom(24000 + i * 1307) + bytes([80 + i]) * 257
        value = checksum(data)
        while value in values:
            data += bytes([i])
            value = checksum(data)
        payloads.append(data)
        values.add(value)

    first = assert_artifact(replace_name, payloads[0])
    errors = []
    stop = threading.Event()
    link_path = os.path.join(BY_NAME, replace_name)
    allowed_latest = set(values) | {duplicate_checksum}
    allowed_targets = {f"../objects/{v}" for v in values}

    def reader():
        while not stop.is_set():
            try:
                if not os.path.islink(link_path):
                    errors.append("by-name symlink was temporarily absent")
                    return
                target = os.readlink(link_path)
                if target not in allowed_targets:
                    errors.append(f"invalid or partial symlink target: {target!r}")
                    return
                with open(LATEST, "rb") as f:
                    raw = f.read()
                valid_latest = {f"{v}\n".encode() for v in allowed_latest}
                if raw not in valid_latest:
                    errors.append(f"invalid or partial latest.txt: {raw!r}")
                    return
            except (FileNotFoundError, OSError) as exc:
                errors.append(f"atomic output temporarily unavailable: {exc}")
                return

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    try:
        for data in payloads[1:]:
            assert_artifact(replace_name, data)
    finally:
        stop.set()
        thread.join(timeout=2)
    assert not errors, errors[0] if errors else "atomic reader failed"

    # Run the independently compiled source too, preventing an unrelated executable
    # at /home/user/curator from substituting for curator.c.
    kill_curator_processes()
    source_proc = launch(verified)
    assert_artifact(f"source_{uuid.uuid4().hex}.bin", os.urandom(77777))

    # Leave the required submitted executable actively watching when verification ends.
    kill_curator_processes()
    launch(binary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
