#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import os
import re
import secrets
import signal
import struct
import subprocess
import time


def test_tracker_files_exist():
    """Check that the C source and executable exist."""
    assert os.path.isfile("/home/user/tracker.c"), "/home/user/tracker.c does not exist."
    assert os.path.isfile("/home/user/tracker"), "/home/user/tracker does not exist."
    assert os.access("/home/user/tracker", os.X_OK), "/home/user/tracker is not executable."


def test_configs_directory_exists():
    """Check that the configs directory exists."""
    assert os.path.isdir("/home/user/configs"), "/home/user/configs directory does not exist."


def test_journal_dump_exists():
    """Check that the hex dump was generated."""
    assert os.path.isfile("/home/user/journal_dump.txt"), "/home/user/journal_dump.txt does not exist."


def test_config_journal_binary():
    """Check the size and contents of the binary journal file."""
    journal_path = "/home/user/config_journal.bin"
    assert os.path.isfile(journal_path), f"{journal_path} does not exist."

    file_size = os.path.getsize(journal_path)
    assert file_size == 584, f"Expected journal file size to be 584 bytes, but got {file_size} bytes."

    with open(journal_path, "rb") as f:
        data = f.read()

    assert len(data) == 584, "Read length does not match expected 584 bytes."

    record1 = data[0:292]
    record2 = data[292:584]

    def parse_record(record_bytes):
        filename_bytes, length, content_bytes = struct.unpack("<32sI256s", record_bytes)
        filename = filename_bytes.rstrip(b'\x00').decode('utf-8', errors='replace')
        return filename, length, content_bytes

    parsed_records = {
        parse_record(record1)[0]: parse_record(record1),
        parse_record(record2)[0]: parse_record(record2),
    }

    assert "app.conf" in parsed_records, "Record for app.conf not found in journal."
    assert "user.conf" in parsed_records, "Record for user.conf not found in journal."

    app_filename, app_length, app_content = parsed_records["app.conf"]
    assert app_length == 6, f"Expected length 6 for app.conf, got {app_length}"
    expected_app_content = b"Caf\xc3\xa9\n"
    assert app_content.startswith(expected_app_content), "Content for app.conf does not match expected UTF-8."

    user_filename, user_length, user_content = parsed_records["user.conf"]
    assert user_length == 6, f"Expected length 6 for user.conf, got {user_length}"
    expected_user_content = b"Ni\xc3\xb1o\n"
    assert user_content.startswith(expected_user_content), "Content for user.conf does not match expected UTF-8."


def test_journal_dump_is_canonical():
    expected = subprocess.check_output(["hexdump", "-C", "/home/user/config_journal.bin"])
    with open("/home/user/journal_dump.txt", "rb") as f:
        actual = f.read()
    assert actual == expected, "journal_dump.txt is not the canonical dump of config_journal.bin"


def _stop_existing_trackers():
    target = "/home/user/tracker"
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            executable = os.readlink(f"/proc/{entry}/exe")
            if executable == target or executable == target + " (deleted)":
                os.kill(int(entry), signal.SIGKILL)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass


def _wait_for_size(path, wanted, proc, timeout=4.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        assert proc.poll() is None, "tracker exited while monitoring"
        size = os.path.getsize(path) if os.path.exists(path) else 0
        assert size <= wanted, f"tracker wrote unexpected extra records ({size} bytes)"
        if size == wanted:
            return
        time.sleep(0.05)
    size = os.path.getsize(path) if os.path.exists(path) else 0
    raise AssertionError(f"journal did not reach {wanted} bytes; got {size}")


def _write_event(directory, name, payload):
    path = os.path.join(directory, name)
    with open(path, "wb") as f:
        f.write(payload)
        f.flush()
        os.fsync(f.fileno())


def _read_records(path):
    with open(path, "rb") as f:
        data = f.read()
    assert len(data) % 292 == 0
    result = {}
    for offset in range(0, len(data), 292):
        raw_name, length, content = struct.unpack("<32sI256s", data[offset:offset + 292])
        assert b"\x00" in raw_name, "filename field is not null-padded"
        name = raw_name.split(b"\x00", 1)[0].decode("utf-8")
        assert raw_name[len(name.encode("utf-8")):] == b"\x00" * (32 - len(name.encode("utf-8")))
        assert name not in result, f"duplicate record for {name}"
        result[name] = (length, content)
    return result


def test_tracker_source_and_live_behavior():
    source_path = "/home/user/tracker.c"
    executable = "/home/user/tracker"
    journal = "/home/user/config_journal.bin"
    config_dir = "/home/user/configs"

    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "tracker must be a compiled executable"

    with open(source_path, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    required = [
        r"inotify_init(?:1)?\s*\(", r"inotify_add_watch\s*\(", r"IN_CLOSE_WRITE",
        r"iconv_open\s*\(", r"iconv\s*\(", r"fcntl\s*\(", r"F_WRLCK", r"F_UNLCK"
    ]
    for pattern in required:
        assert re.search(pattern, source), f"tracker.c is missing required implementation element: {pattern}"

    compile_result = subprocess.run(
        ["gcc", source_path, "-o", "/tmp/tracker_from_source"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert compile_result.returncode == 0, "tracker.c does not compile with gcc: " + compile_result.stderr.decode(errors="replace")

    _stop_existing_trackers()
    os.makedirs(config_dir, exist_ok=True)
    with open(journal, "wb"):
        pass

    token = secrets.token_hex(5)
    cases = {
        f"alpha_{token}.cfg": b"A\xe9" + secrets.token_bytes(4) + b"\xf1\n",
        f"beta_{token}.cfg": b"Z\xfc\xdf" + secrets.token_bytes(5) + b"\n",
    }
    # Avoid embedded bytes only where they would make expected text less useful;
    # every byte is nevertheless valid ISO-8859-1.
    cases = {name: bytes((b if b != 0 else 65) for b in payload) for name, payload in cases.items()}
    lock_name = f"lock_{token}.cfg"
    lock_payload = b"Locked-\xe9-\xf1\n"
    long_name = f"long_{token}.cfg"
    long_payload = b"Q" * 300

    proc = subprocess.Popen([executable], cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        time.sleep(0.6)
        assert proc.poll() is None, "tracker exited before receiving events"

        for name, payload in cases.items():
            _write_event(config_dir, name, payload)
        _wait_for_size(journal, 2 * 292, proc)

        records = _read_records(journal)
        assert set(records) == set(cases)
        for name, payload in cases.items():
            expected = payload.decode("iso-8859-1").encode("utf-8")
            length, content = records[name]
            assert length == len(expected), f"wrong converted length for {name}"
            assert content[:length] == expected, f"wrong ISO-8859-1 to UTF-8 conversion for {name}"
            assert content[length:] == b"\x00" * (256 - length), f"content for {name} is not null-padded"

        with open(journal, "r+b", buffering=0) as lock_file:
            fcntl.lockf(lock_file, fcntl.LOCK_EX)
            _write_event(config_dir, lock_name, lock_payload)
            time.sleep(1.2)
            assert proc.poll() is None, "tracker exited while waiting for the journal lock"
            assert os.path.getsize(journal) == 2 * 292, "tracker appended without respecting the exclusive fcntl lock"
            fcntl.lockf(lock_file, fcntl.LOCK_UN)

        _wait_for_size(journal, 3 * 292, proc)
        _write_event(config_dir, long_name, long_payload)
        _wait_for_size(journal, 4 * 292, proc)

        records = _read_records(journal)
        expected_lock = lock_payload.decode("iso-8859-1").encode("utf-8")
        assert records[lock_name][0] == len(expected_lock)
        assert records[lock_name][1][:len(expected_lock)] == expected_lock
        assert records[lock_name][1][len(expected_lock):] == b"\x00" * (256 - len(expected_lock))
        assert records[long_name][0] == 256, "truncated content_length must be 256"
        assert records[long_name][1] == b"Q" * 256, "content longer than 256 bytes was not truncated correctly"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
