#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import re
import secrets
import shutil
import subprocess
import time

DAEMON = "/home/user/doc_daemon"
WATCH_DIR = "/home/user/doc_watch"
ARCHIVE = "/home/user/doc_archive.bin"
WORKSPACE = "/home/user/workspace/doc_aggregator"


def reset_state():
    os.makedirs(WATCH_DIR, exist_ok=True)
    for name in os.listdir(WATCH_DIR):
        path = os.path.join(WATCH_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
    if os.path.exists(ARCHIVE):
        os.remove(ARCHIVE)


def stop_process(process):
    process.terminate()
    try:
        process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=3)


def encode_record(title, lines):
    title_bytes = title.encode("utf-8")
    content_bytes = "\n".join(lines).encode("utf-8")
    assert len(title_bytes) <= 255
    return (
        b"DOC1"
        + bytes([len(title_bytes)])
        + title_bytes
        + len(content_bytes).to_bytes(4, byteorder="little")
        + content_bytes
    )


def wait_for_exact_archive(expected, timeout=6):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        if os.path.exists(ARCHIVE):
            with open(ARCHIVE, "rb") as f:
                last = f.read()
            if last == expected:
                # Ensure a duplicate notification does not append another copy.
                time.sleep(0.5)
                with open(ARCHIVE, "rb") as f:
                    stable = f.read()
                assert stable == expected, (
                    f"Archive changed after reaching expected contents. "
                    f"Expected: {expected.hex()} Got: {stable.hex()}"
                )
                return
        time.sleep(0.1)
    got = b"" if last is None else last
    raise AssertionError(
        f"Archive did not reach expected contents.\n"
        f"Expected: {expected.hex()}\nGot:      {got.hex()}"
    )


def test_daemon_executable():
    """Keep the original executable checks and ensure the deliverable is a compiled binary."""
    assert os.path.exists(DAEMON), f"Daemon executable not found at {DAEMON}"
    assert os.access(DAEMON, os.X_OK), f"Daemon at {DAEMON} is not executable"
    with open(DAEMON, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The final executable is not a compiled ELF binary"


def test_original_daemon_behavior():
    """Retain the original fixed behavioral assertion."""
    reset_state()
    process = subprocess.Popen([DAEMON], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1)
        test_file = os.path.join(WATCH_DIR, "test1.txt")
        with open(test_file, "w", encoding="utf-8") as f:
            f.write("Some random chatter.\n")
            f.write(">>>DOC: Auth Setup\n")
            f.write("Use OAuth2.\n")
            f.write("Token in header.\n")
            f.write("<<<END\n")
            f.write("Garbage text.\n")
        time.sleep(2)
    finally:
        stop_process(process)

    assert os.path.exists(ARCHIVE), f"Archive file {ARCHIVE} was not created by the daemon"
    with open(ARCHIVE, "rb") as f:
        data = f.read()

    expected_magic = b"DOC1"
    expected_title = b"Auth Setup"
    expected_title_len = bytes([len(expected_title)])
    expected_content = b"Use OAuth2.\nToken in header."
    expected_content_len = len(expected_content).to_bytes(4, byteorder="little")
    expected_data = expected_magic + expected_title_len + expected_title + expected_content_len + expected_content
    assert data == expected_data, (
        f"Archive data mismatch.\nExpected: {expected_data.hex()}\nGot:      {data.hex()}"
    )


def test_randomized_parsing_and_real_locking():
    """Exercise unpredictable records and verify that an external exclusive lock is honored."""
    reset_state()

    nonce = secrets.token_hex(12)
    title1 = "Build " + secrets.token_hex(5)
    title2 = "Deploy " + secrets.token_hex(6)
    lines1 = ["first-" + nonce, "second value " + secrets.token_hex(9), ""]
    lines2 = ["unicode café " + secrets.token_hex(7), "final-" + secrets.token_hex(10)]
    expected_first = encode_record(title1, lines1) + encode_record(title2, lines2)

    # Lock the exact archive inode before starting the daemon. A conforming daemon
    # must block its append until this lock is released.
    lock_file = open(ARCHIVE, "w+b", buffering=0)
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    locked = True
    original_stat = os.fstat(lock_file.fileno())
    process = subprocess.Popen([DAEMON], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        time.sleep(1)
        incoming = os.path.join("/tmp", "incoming-" + secrets.token_hex(8))
        destination = os.path.join(WATCH_DIR, "batch-" + secrets.token_hex(8) + ".txt")
        with open(incoming, "w", encoding="utf-8") as f:
            f.write("ignored " + secrets.token_hex(8) + "\n")
            f.write("<<<END\n")
            f.write(f">>>DOC: {title1}\n")
            for line in lines1:
                f.write(line + "\n")
            f.write("<<<END\n")
            f.write(">>>DOC malformed header\nignored malformed body\n<<<END\n")
            f.write(f">>>DOC: {title2}\n")
            for line in lines2:
                f.write(line + "\n")
            f.write("<<<END\n")
            f.write("trailing noise " + secrets.token_hex(8) + "\n")
        os.replace(incoming, destination)

        time.sleep(2.5)
        assert process.poll() is None, "Daemon exited while processing a watched file"
        archive_stat = os.stat(ARCHIVE)
        assert (archive_stat.st_dev, archive_stat.st_ino) == (original_stat.st_dev, original_stat.st_ino), (
            "Daemon replaced the locked archive instead of locking and appending to it"
        )
        lock_file.seek(0)
        assert lock_file.read() == b"", "Daemon wrote to the archive while another process held LOCK_EX"

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        locked = False
        wait_for_exact_archive(expected_first)

        # Send a second unpredictable file to ensure output is derived from input
        # and appended rather than being a one-shot hardcoded response.
        title3 = "Notes " + secrets.token_hex(7)
        lines3 = ["alpha " + secrets.token_hex(11), "beta " + secrets.token_hex(13)]
        expected_all = expected_first + encode_record(title3, lines3)
        incoming2 = os.path.join("/tmp", "incoming-" + secrets.token_hex(8))
        destination2 = os.path.join(WATCH_DIR, "batch-" + secrets.token_hex(8) + ".log")
        with open(incoming2, "w", encoding="utf-8") as f:
            f.write("outside\n")
            f.write(f">>>DOC: {title3}\n")
            for line in lines3:
                f.write(line + "\n")
            f.write("<<<END\n")
            f.write("outside again\n")
        os.replace(incoming2, destination2)
        wait_for_exact_archive(expected_all)
    finally:
        if locked:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()
        stop_process(process)


def test_source_code_locking():
    """Retain the original source/project and locking assertion."""
    assert os.path.exists(WORKSPACE), f"Workspace directory {WORKSPACE} not found"
    assert os.path.isfile(os.path.join(WORKSPACE, "Cargo.toml")), "Rust project is missing Cargo.toml"

    found_lock = False
    lock_keywords = ["lock_exclusive", "flock", "try_lock_exclusive", "lock"]
    for root, _, files in os.walk(WORKSPACE):
        for filename in files:
            if filename.endswith(".rs"):
                file_path = os.path.join(root, filename)
                with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                if any(keyword in content for keyword in lock_keywords):
                    found_lock = True
                    break
        if found_lock:
            break

    assert found_lock, (
        "Could not find any standard file locking mechanism "
        "(e.g., lock_exclusive, flock) in the Rust source code."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
