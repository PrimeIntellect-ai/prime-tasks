#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_data_organizer.py
import json
import os
import shutil
import signal
import stat
import subprocess
import tarfile
import time
import uuid

HOME = "/home/user"
PROJECT = f"{HOME}/data_organizer"
BINARY = f"{PROJECT}/target/release/data_organizer"
RUN_SCRIPT = f"{HOME}/run_and_test.sh"
INCOMING = f"{HOME}/incoming"
PROCESSED = f"{HOME}/processed"
DEBUG = f"{HOME}/debug_chunks"
STATUS = f"{HOME}/status.log"
LATEST = f"{HOME}/latest_data.txt"
RAW = f"{INCOMING}/raw_data.txt"
ARCHIVE = f"{PROCESSED}/archive.tar.gz"
EXPECTED_COUNTS = {"chunk_0.txt": 50, "chunk_1.txt": 50, "chunk_2.txt": 25}


def clean_outputs():
    for path in (INCOMING, PROCESSED, DEBUG):
        shutil.rmtree(path, ignore_errors=True)
        os.makedirs(path, exist_ok=True)
    for path in (STATUS, LATEST):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def run_with_timeout(command, timeout, cwd=None):
    proc = subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        return proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        raise AssertionError(f"Command timed out: {command}")


def organizer_pids():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if argv and os.path.realpath(argv[0]) == os.path.realpath(BINARY):
                found.append(int(entry))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def assert_project():
    assert os.path.isfile(f"{PROJECT}/Cargo.toml"), "Cargo.toml is missing"
    assert os.path.isfile(f"{PROJECT}/src/main.rs"), "src/main.rs is missing"
    assert os.path.isfile(RUN_SCRIPT), "run_and_test.sh is missing"
    assert subprocess.run(["bash", "-n", RUN_SCRIPT]).returncode == 0, "run_and_test.sh has invalid shell syntax"

    result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f"Cargo project is invalid: {result.stderr}"
    metadata = json.loads(result.stdout)
    package = next((p for p in metadata["packages"] if p["name"] == "data_organizer"), None)
    assert package is not None, "Rust package must be named data_organizer"
    dependencies = {d["name"] for d in package["dependencies"]}
    for required in ("notify", "tar", "flate2"):
        assert required in dependencies, f"Cargo.toml is missing the {required} dependency"

    with open(f"{PROJECT}/src/main.rs", encoding="utf-8") as f:
        source = f.read()
    for required in ("notify", "tar", "flate2"):
        assert required in source, f"src/main.rs does not use the {required} crate"


def archive_members():
    assert os.path.exists(ARCHIVE), f"{ARCHIVE} does not exist."
    assert tarfile.is_tarfile(ARCHIVE), f"{ARCHIVE} is not a valid tar archive."
    result = {}
    with tarfile.open(ARCHIVE, "r:gz") as tar:
        names = tar.getnames()
        base_names = [os.path.basename(name) for name in names]
        for chunk in EXPECTED_COUNTS:
            assert chunk in base_names, f"{chunk} is missing from the archive {ARCHIVE}."
            matches = [m for m in tar.getmembers() if m.isfile() and os.path.basename(m.name) == chunk]
            assert len(matches) == 1, f"Expected one regular archive member named {chunk}"
            extracted = tar.extractfile(matches[0])
            assert extracted is not None
            result[chunk] = extracted.read()
    return result


def find_hardlink_peer(path):
    wanted = os.stat(path)
    for root, dirs, files in os.walk(HOME, followlinks=False):
        if os.path.realpath(root) == os.path.realpath(DEBUG):
            dirs[:] = []
            continue
        for name in files:
            candidate = os.path.join(root, name)
            try:
                info = os.lstat(candidate)
            except FileNotFoundError:
                continue
            if stat.S_ISREG(info.st_mode) and info.st_dev == wanted.st_dev and info.st_ino == wanted.st_ino:
                return candidate
    return None


def assert_final_state(expected_lines=None):
    # Preserve the original status assertion.
    assert os.path.exists(STATUS), f"{STATUS} does not exist."
    with open(STATUS, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert "SUCCESS" in content, f"{STATUS} does not contain 'SUCCESS'."

    # Preserve the original symlink assertion.
    assert os.path.islink(LATEST), f"{LATEST} is not a symbolic link."
    actual_target = os.readlink(LATEST)
    if not os.path.isabs(actual_target):
        actual_target = os.path.normpath(os.path.join(os.path.dirname(LATEST), actual_target))
    assert actual_target == RAW, f"Symlink points to {actual_target}, expected {RAW}."

    # Preserve the original raw-data assertion.
    assert os.path.exists(RAW), f"{RAW} does not exist."
    with open(RAW, "r", encoding="utf-8") as f:
        raw_lines = f.readlines()
    assert len(raw_lines) == 125, f"{RAW} has {len(raw_lines)} lines, expected 125."
    if expected_lines is not None:
        assert raw_lines == expected_lines, "The watched input file was changed or replaced"

    assert os.path.isdir(DEBUG), f"{DEBUG} is not a directory."
    archived = archive_members()
    for index, (chunk, expected_count) in enumerate(EXPECTED_COUNTS.items()):
        chunk_path = os.path.join(DEBUG, chunk)
        assert os.path.exists(chunk_path), f"Chunk file {chunk_path} does not exist."
        with open(chunk_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        assert len(lines) == expected_count, f"{chunk} has {len(lines)} lines, expected {expected_count}."

        # Keep the original link-count check, then require a real second directory entry.
        info = os.stat(chunk_path)
        assert info.st_nlink >= 1, f"{chunk_path} does not have a valid link count."
        assert info.st_nlink > 1, f"{chunk_path} is an ordinary file, not a hard link"
        peer = find_hardlink_peer(chunk_path)
        assert peer is not None, f"No original file shares an inode with {chunk_path}"

        with open(chunk_path, "rb") as f:
            chunk_bytes = f.read()
        assert archived[chunk] == chunk_bytes, f"Archive contents for {chunk} differ from the generated chunk"
        if expected_lines is not None:
            start = index * 50
            expected_bytes = "".join(expected_lines[start:start + 50]).encode()
            assert chunk_bytes == expected_bytes, f"{chunk} does not contain the correct input lines"


def verify_required_script():
    clean_outputs()
    rc = run_with_timeout(["bash", RUN_SCRIPT], 240, cwd=HOME)
    assert rc == 0, f"run_and_test.sh exited with status {rc}"
    assert os.path.isfile(BINARY), "run_and_test.sh did not build the release executable"
    assert_final_state()

    deadline = time.time() + 10
    while organizer_pids() and time.time() < deadline:
        time.sleep(0.1)
    assert not organizer_pids(), "Organizer did not exit cleanly after writing status.log"


def verify_live_watcher_with_unknown_input():
    clean_outputs()
    token = uuid.uuid4().hex
    expected = [f"{token}-record-{i:03d}\n" for i in range(1, 126)]

    proc = subprocess.Popen(
        [BINARY],
        cwd=PROJECT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        # The input does not exist until after the service has had time to start watching.
        time.sleep(2)
        staging = f"/tmp/raw_data-{token}.txt"
        with open(staging, "w", encoding="utf-8") as f:
            f.writelines(expected)
        os.replace(staging, RAW)

        deadline = time.time() + 30
        while not os.path.exists(STATUS) and proc.poll() is None and time.time() < deadline:
            time.sleep(0.1)
        assert os.path.exists(STATUS), "Live watcher did not process the newly dropped file"
        try:
            rc = proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            raise AssertionError("Organizer did not exit after processing the file")
        assert rc == 0, f"Organizer exited with status {rc}"
        assert_final_state(expected)
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()


assert_project()
verify_required_script()
verify_live_watcher_with_unknown_input()
PY_EOF

if python3 /tmp/test_data_organizer.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
