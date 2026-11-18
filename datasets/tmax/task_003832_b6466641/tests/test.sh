#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'WRAP_EOF' > /tmp/atomic_audit.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static void log_event(const char *kind, const char *a, const char *b) {
    const char *path = getenv("ATOMIC_AUDIT_LOG");
    if (!path) return;
    char buf[4096];
    int n = b ? snprintf(buf, sizeof(buf), "%s|%s|%s\n", kind, a, b)
              : snprintf(buf, sizeof(buf), "%s|%s\n", kind, a);
    if (n <= 0) return;
    if (n > (int)sizeof(buf)) n = sizeof(buf);
    int fd = syscall(SYS_openat, AT_FDCWD, path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, buf, (size_t)n);
        syscall(SYS_close, fd);
    }
}

int fsync(int fd) {
    static int (*real_fsync)(int);
    if (!real_fsync) real_fsync = dlsym(RTLD_NEXT, "fsync");
    int rc = real_fsync(fd);
    if (rc == 0) {
        char value[32];
        snprintf(value, sizeof(value), "%d", fd);
        log_event("F", value, NULL);
    }
    return rc;
}

int fdatasync(int fd) {
    static int (*real_fdatasync)(int);
    if (!real_fdatasync) real_fdatasync = dlsym(RTLD_NEXT, "fdatasync");
    int rc = real_fdatasync(fd);
    if (rc == 0) {
        char value[32];
        snprintf(value, sizeof(value), "%d", fd);
        log_event("D", value, NULL);
    }
    return rc;
}

int rename(const char *oldpath, const char *newpath) {
    static int (*real_rename)(const char *, const char *);
    if (!real_rename) real_rename = dlsym(RTLD_NEXT, "rename");
    int rc = real_rename(oldpath, newpath);
    if (rc == 0) log_event("R", oldpath, newpath);
    return rc;
}
WRAP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import secrets
import struct
import subprocess
import tarfile
from pathlib import Path

HOME = Path("/home/user")
SOURCE = HOME / "convert_logs.c"
BINARY = HOME / "convert_logs"
EXTRACTED = HOME / "extracted_logs"
PROCESSED = HOME / "processed_logs"
AUDIT_LIB = "/tmp/atomic_audit.so"

EXPECTED_CSV = {
    "log_0001.csv": [
        "Timestamp,EventID,Severity,Payload",
        "1600000000,10,1,System start",
        "1600000005,12,2,Warning temp",
    ],
    "log_0002.csv": [
        "Timestamp,EventID,Severity,Payload",
        "1600000010,15,0,All good",
    ],
    "log_0003.csv": [
        "Timestamp,EventID,Severity,Payload",
        "1600000020,99,3,Fatal error",
    ],
}


def archived_blogs():
    found = []
    master = HOME / "backups/master_backup.tar.gz"
    with tarfile.open(master, "r:gz") as outer:
        for member in outer.getmembers():
            if not member.isfile() or not member.name.endswith(".tar"):
                continue
            stream = outer.extractfile(member)
            assert stream is not None
            with tarfile.open(fileobj=io.BytesIO(stream.read()), mode="r:") as inner:
                for item in inner.getmembers():
                    if item.isfile() and item.name.endswith(".blog"):
                        data = inner.extractfile(item)
                        assert data is not None
                        found.append((os.path.basename(item.name), data.read()))
    found.sort(key=lambda pair: pair[0])
    return found


def test_tar_slip_prevented():
    state_file = HOME / "system_state.json"
    assert state_file.exists(), f"Critical file {state_file} is missing!"
    assert state_file.read_text().strip() == "SECURE_STATE", "system_state.json was altered"


def test_extracted_logs_are_complete_flattened_and_renamed():
    expected = archived_blogs()
    assert len(expected) == 3
    expected_names = [f"log_{i:04d}.blog" for i in range(1, len(expected) + 1)]
    actual_names = sorted(p.name for p in EXTRACTED.iterdir())
    assert actual_names == expected_names, "Extracted logs are missing, extra, nested, or incorrectly named"
    for renamed, (_, expected_bytes) in zip(expected_names, expected):
        path = EXTRACTED / renamed
        assert path.is_file() and not path.is_symlink()
        assert path.read_bytes() == expected_bytes, f"{renamed} does not match its archived source"


def test_csv_files_exist_and_are_exact():
    actual = sorted(p.name for p in PROCESSED.iterdir())
    assert actual == sorted(EXPECTED_CSV), "Processed directory has missing or unexpected files"
    for filename, expected_lines in EXPECTED_CSV.items():
        path = PROCESSED / filename
        assert path.is_file() and not path.is_symlink(), f"Missing expected CSV file: {path}"
        assert path.read_text().splitlines() == expected_lines, f"Malformed or incorrect CSV: {path}"
        assert path.read_text().startswith("Timestamp,EventID,Severity,Payload")


def test_c_program_exists_and_uses_atomic_writes():
    assert SOURCE.exists(), f"C source code not found at {SOURCE}"
    code = SOURCE.read_text()
    assert re.search(r"\brename\s*\(", code), "The C program does not appear to use POSIX rename()"
    assert BINARY.is_file(), f"Compiled converter not found at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Converter is not executable: {BINARY}"
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "convert_logs is not a compiled ELF executable"


def normalized(path, cwd):
    return os.path.normpath(path if os.path.isabs(path) else os.path.join(cwd, path))


def atomic_trace_is_valid(log_path, cwd, destination):
    if not log_path.exists():
        return False
    events = log_path.read_text(errors="replace").splitlines()
    for index, event in enumerate(events):
        parts = event.split("|", 2)
        if len(parts) != 3 or parts[0] != "R":
            continue
        oldpath, newpath = parts[1], parts[2]
        if normalized(newpath, cwd) != os.path.normpath(str(destination)):
            continue
        if not oldpath.endswith(".tmp"):
            return False
        return any(prior.startswith(("F|", "D|")) for prior in events[:index])
    return False


def test_converter_on_fresh_input_and_runtime_atomic_write(tmp_path):
    token = secrets.token_hex(12)
    records = [
        (305419896, 513, 7, "fresh-" + token),
        (4000000001, 65530, 2, "second-" + token[::-1]),
    ]
    data = bytearray(b"BLOG")
    for timestamp, event_id, severity, payload in records:
        raw = payload.encode("ascii")
        data.extend(struct.pack("<IHBB", timestamp, event_id, severity, len(raw)))
        data.extend(raw)
    expected = "Timestamp,EventID,Severity,Payload\n" + "".join(
        f"{ts},{event},{severity},{payload}\n"
        for ts, event, severity, payload in records
    )

    attempts = []
    for mode in ("file-output", "directory-output", "input-only"):
        work = tmp_path / mode
        input_dir = work / "inputs"
        output_dir = work / "outputs"
        input_dir.mkdir(parents=True)
        output_dir.mkdir()
        input_path = input_dir / "log_9001.blog"
        input_path.write_bytes(data)
        if mode == "file-output":
            destination = output_dir / "log_9001.csv"
            command = [str(BINARY), str(input_path), str(destination)]
        elif mode == "directory-output":
            destination = output_dir / "log_9001.csv"
            command = [str(BINARY), str(input_dir), str(output_dir)]
        else:
            destination = input_dir / "log_9001.csv"
            command = [str(BINARY), str(input_path)]

        audit_log = work / "atomic.log"
        env = os.environ.copy()
        env["LD_PRELOAD"] = AUDIT_LIB
        env["ATOMIC_AUDIT_LOG"] = str(audit_log)
        try:
            result = subprocess.run(command, cwd=work, env=env, timeout=10,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (subprocess.TimeoutExpired, OSError) as exc:
            attempts.append(f"{mode}: {exc}")
            continue

        if result.returncode != 0 or not destination.is_file():
            attempts.append(f"{mode}: return code {result.returncode}, no output")
            continue
        if destination.read_text() != expected:
            attempts.append(f"{mode}: incorrect CSV output")
            continue
        assert atomic_trace_is_valid(audit_log, str(work), destination), (
            "Fresh conversion did not fsync/fdatasync a temporary .tmp file before rename() "
            "to the final CSV"
        )
        return

    raise AssertionError("Compiled converter could not convert a fresh BLOG input: " + "; ".join(attempts))
TEST_EOF

if gcc -shared -fPIC -O2 -o /tmp/atomic_audit.so /tmp/atomic_audit.c -ldl \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
