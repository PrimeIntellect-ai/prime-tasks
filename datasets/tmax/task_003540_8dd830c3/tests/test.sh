#!/bin/bash
set -e
mkdir -p /logs/verifier

cat > /tmp/verify_process_log.py <<'PY'
import ctypes
import os
import secrets
import shutil
import struct
import subprocess
import time

SOURCE = "/home/user/process_log.rs"
INPUT = "/home/user/legacy_system.log"
STAGING = "/home/user/staging"
OUTPUT = os.path.join(STAGING, "clean_system.log")
BINARY = "/tmp/process_log_verified"

ORIGINAL = (
    b"LOG ENTRY 1: System started\n"
    b"LOG ENTRY 2: User login [SECRET_ID]\n"
    b"LOG ENTRY 3: R\xe9sum\xe9 processed for [SECRET_ID]\n"
    b"LOG ENTRY 4: System shutdown\n"
)
ORIGINAL_EXPECTED = (
    "LOG ENTRY 1: System started\n"
    "LOG ENTRY 2: User login [REDACTED]\n"
    "LOG ENTRY 3: Résumé processed for [REDACTED]\n"
    "LOG ENTRY 4: System shutdown\n"
)

IN_MODIFY = 0x00000002
IN_CLOSE_WRITE = 0x00000008
IN_OPEN = 0x00000020
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
WATCH_MASK = IN_MODIFY | IN_CLOSE_WRITE | IN_OPEN | IN_MOVED_FROM | IN_MOVED_TO | IN_CREATE
FINAL_DIRECT_EVENTS = IN_MODIFY | IN_CLOSE_WRITE | IN_OPEN | IN_CREATE

libc = ctypes.CDLL(None, use_errno=True)
libc.inotify_init1.argtypes = [ctypes.c_int]
libc.inotify_init1.restype = ctypes.c_int
libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
libc.inotify_add_watch.restype = ctypes.c_int


def expected_for(raw):
    return raw.decode("latin-1").replace("[SECRET_ID]", "[REDACTED]").encode("utf-8")


def clear_staging():
    os.makedirs(STAGING, exist_ok=True)
    for entry in os.scandir(STAGING):
        if entry.is_dir(follow_symlinks=False):
            shutil.rmtree(entry.path)
        else:
            os.unlink(entry.path)


def read_events(fd):
    events = []
    time.sleep(0.02)
    while True:
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            break
        if not data:
            break
        offset = 0
        while offset < len(data):
            wd, mask, cookie, name_len = struct.unpack_from("iIII", data, offset)
            offset += 16
            name_raw = data[offset:offset + name_len]
            offset += name_len
            name = name_raw.split(b"\0", 1)[0].decode("utf-8", "surrogateescape")
            events.append((mask, cookie, name))
    return events


def run_case(raw, label):
    clear_staging()
    with open(INPUT, "wb") as f:
        f.write(raw)

    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0, f"inotify_init1 failed for {label}: errno {ctypes.get_errno()}"
    try:
        wd = libc.inotify_add_watch(fd, STAGING.encode(), WATCH_MASK)
        assert wd >= 0, f"Could not monitor staging directory for {label}: errno {ctypes.get_errno()}"

        result = subprocess.run(
            [BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, (
            f"Compiled Rust program failed for {label} with exit code {result.returncode}. "
            f"stderr: {result.stderr.decode('utf-8', 'replace')}"
        )
        events = read_events(fd)
    finally:
        os.close(fd)

    assert os.path.exists(OUTPUT), f"{OUTPUT} was not produced for {label}."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a regular file for {label}."
    with open(OUTPUT, "rb") as f:
        actual = f.read()

    expected = expected_for(raw)
    assert actual == expected, f"Incorrect Latin-1 conversion or redaction for {label}."
    try:
        text = actual.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AssertionError(f"Output is not valid UTF-8 for {label}: {exc}")
    assert "[SECRET_ID]" not in text, f"A secret identifier remains for {label}."

    move_to_indexes = [
        i for i, (mask, cookie, name) in enumerate(events)
        if (mask & IN_MOVED_TO) and name == "clean_system.log"
    ]
    assert move_to_indexes, (
        f"No executed atomic rename into {OUTPUT} was observed for {label}."
    )
    move_index = move_to_indexes[-1]
    move_cookie = events[move_index][1]
    matching_sources = [
        name for mask, cookie, name in events
        if (mask & IN_MOVED_FROM) and cookie == move_cookie
    ]
    assert matching_sources, (
        f"The final output rename for {label} did not originate from a temporary file "
        f"in {STAGING}."
    )
    assert all(name != "clean_system.log" for name in matching_sources), (
        f"The rename source was not a distinct temporary file for {label}."
    )

    direct_before_rename = [
        (mask, name) for mask, cookie, name in events[:move_index]
        if name == "clean_system.log" and (mask & FINAL_DIRECT_EVENTS)
    ]
    assert not direct_before_rename, (
        f"The final output was opened, created, or modified directly before the rename "
        f"for {label}; the write was not atomic."
    )


def main():
    # Preserve the original final-state assertions: the agent must already have run it.
    assert os.path.exists(OUTPUT), f"File {OUTPUT} does not exist. Did the Rust program run successfully?"
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."
    with open(OUTPUT, "rb") as f:
        initial_raw = f.read()
    try:
        initial_text = initial_raw.decode("utf-8")
    except UnicodeDecodeError:
        raise AssertionError(f"The file {OUTPUT} is not valid UTF-8.")
    assert "[SECRET_ID]" not in initial_text, "The string [SECRET_ID] was not completely redacted."
    assert "[REDACTED]" in initial_text, "The string [REDACTED] was not found in the output."
    assert "Résumé" in initial_text, "The ISO-8859-1 characters were not correctly converted to UTF-8."
    assert initial_text == ORIGINAL_EXPECTED, f"Content of {OUTPUT} does not match the expected output."

    assert os.path.exists(SOURCE), f"Rust source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    with open(SOURCE, "r", encoding="utf-8", errors="ignore") as f:
        source_code = f.read()
    assert "rename" in source_code, "The Rust program does not appear to use an atomic rename operation."

    compile_result = subprocess.run(
        ["rustc", SOURCE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        "process_log.rs did not compile directly with rustc: "
        + compile_result.stderr.decode("utf-8", "replace")
    )

    nonce = secrets.token_hex(24).encode("ascii")
    cases = [
        (ORIGINAL, "original fixture"),
        (
            b"nonce=" + nonce + b"\n"
            b"[SECRET_ID][SECRET_ID]\n"
            b"Latin-1 bytes: \x80\xa3\xc7\xd1\xe9\xf1\xff\n"
            b"near matches: [secret_id] [SECRET_ID ] X[SECRET_ID]Y\n",
            "runtime-generated identifiers and multiple redactions",
        ),
        (
            bytes(range(256)) + b"\nvalue=[SECRET_ID]\n" + secrets.token_bytes(128),
            "complete Latin-1 byte range",
        ),
    ]

    for raw, label in cases:
        run_case(raw, label)

    # Leave the requested original artifact in its expected final state.
    run_case(ORIGINAL, "final restoration")


if __name__ == "__main__":
    main()
PY

if python3 /tmp/verify_process_log.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
