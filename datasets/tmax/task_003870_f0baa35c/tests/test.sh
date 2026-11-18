#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'LOCK_EOF' > /tmp/lockwatch.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int (*real_fcntl_fn)(int, int, ...) = NULL;

static void record_lock_event(int fd, short type) {
    char procpath[64];
    char target[4096];
    const char *logpath = getenv("LOCKWATCH_LOG");
    if (!logpath) return;

    snprintf(procpath, sizeof(procpath), "/proc/self/fd/%d", fd);
    ssize_t n = readlink(procpath, target, sizeof(target) - 1);
    if (n < 0) return;
    target[n] = '\0';
    if (strcmp(target, "/home/user/backups/archive.bin") != 0) return;

    int out = open(logpath, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (out < 0) return;
    const char *msg = type == F_WRLCK ? "LOCK\n" : "UNLOCK\n";
    write(out, msg, strlen(msg));
    close(out);
}

int fcntl(int fd, int cmd, ...) {
    if (!real_fcntl_fn) {
        real_fcntl_fn = dlsym(RTLD_NEXT, "fcntl");
        if (!real_fcntl_fn) _exit(127);
    }

    va_list ap;
    va_start(ap, cmd);
    void *arg = va_arg(ap, void *);
    va_end(ap);

    int rc = real_fcntl_fn(fd, cmd, arg);
    if (rc == 0 && (cmd == F_SETLK || cmd == F_SETLKW) && arg) {
        struct flock *fl = (struct flock *)arg;
        if (fl->l_type == F_WRLCK || fl->l_type == F_UNLCK)
            record_lock_event(fd, fl->l_type);
    }
    return rc;
}
LOCK_EOF

gcc -shared -fPIC -ldl /tmp/lockwatch.c -o /tmp/lockwatch.so

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import pytest

WAL = "/home/user/backups/db.wal"
ARCHIVE = "/home/user/backups/archive.bin"
LOG = "/home/user/backups/process.log"
SOURCE = "/home/user/wal_archiver.c"
PROGRAM = "/home/user/wal_archiver"


def parse_wal(wal_path):
    if not os.path.isfile(wal_path):
        pytest.fail(f"WAL file {wal_path} is missing.")

    with open(wal_path, 'rb') as f:
        data = f.read()

    if not data.startswith(b"BKWAL1\n"):
        pytest.fail("WAL file does not start with BKWAL1\\n")

    pos = 7
    valid_records = []
    while pos < len(data):
        if not data[pos:].startswith(b"BEGIN\n"):
            break
        pos += 6

        nl = data.find(b'\n', pos)
        file_line = data[pos:nl].decode('utf-8')
        pos = nl + 1
        file_path = file_line.split("FILE: ")[1]

        nl = data.find(b'\n', pos)
        size_line = data[pos:nl].decode('utf-8')
        pos = nl + 1
        size = int(size_line.split("SIZE: ")[1])

        nl = data.find(b'\n', pos)
        chk_line = data[pos:nl].decode('utf-8')
        pos = nl + 1
        expected_chk = int(chk_line.split("CHECKSUM: ")[1], 16)

        nl = data.find(b'\n', pos)
        pos = nl + 1
        record_data = data[pos:pos + size]
        pos += size
        nl = data.find(b'\n', pos)
        pos = nl + 1

        if sum(record_data) % 256 == expected_chk:
            valid_records.append({"path": file_path, "data": record_data})
    return valid_records


def expected_outputs(records):
    archive = bytearray()
    log = []
    for r in records:
        path = r["path"].encode('utf-8')
        archive.extend(struct.pack('<I', len(path)))
        archive.extend(path)
        archive.extend(struct.pack('<I', len(r["data"])))
        archive.extend(r["data"])
        log.append(f"ARCHIVED {r['path']} {len(r['data'])} bytes\n")
    return bytes(archive), ''.join(log)


def write_wal(path, records):
    with open(path, 'wb') as f:
        f.write(b"BKWAL1\n")
        for file_path, payload, valid in records:
            checksum = sum(payload) % 256
            if not valid:
                checksum = (checksum + 1) % 256
            f.write(b"BEGIN\n")
            f.write(f"FILE: {file_path}\n".encode())
            f.write(f"SIZE: {len(payload)}\n".encode())
            f.write(f"CHECKSUM: {checksum:02X}\n".encode())
            f.write(b"DATA\n")
            f.write(payload)
            f.write(b"END\n")


def clean_outputs():
    for path in (ARCHIVE, LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def test_compilation_execution_and_real_fcntl_locking():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(PROGRAM), f"Compiled program {PROGRAM} is missing."
    assert os.access(PROGRAM, os.X_OK), f"Compiled program {PROGRAM} is not executable."
    with open(PROGRAM, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{PROGRAM} is not an ELF executable."

    original_wal = open(WAL, 'rb').read()
    subprocess.run(['gcc', SOURCE, '-o', PROGRAM], check=True, timeout=30,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    records = [
        ("/srv/random/a.bin", bytes(range(32)) + b"\x00END\n\xff", True),
        ("/srv/random/rejected.bin", b"must-not-be-archived", False),
        ("/srv/random/empty.dat", b"", True),
        ("/srv/random/text.cfg", b"alpha=7\nbeta=eleven\n", True),
    ]
    expected_records = [{"path": p, "data": d} for p, d, valid in records if valid]
    expected_archive, expected_log = expected_outputs(expected_records)
    lock_log = '/tmp/wal_lock_events.log'

    try:
        write_wal(WAL, records)
        clean_outputs()
        try:
            os.remove(lock_log)
        except FileNotFoundError:
            pass
        env = os.environ.copy()
        env['LD_PRELOAD'] = '/tmp/lockwatch.so'
        env['LOCKWATCH_LOG'] = lock_log
        subprocess.run([PROGRAM], check=True, timeout=15, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        assert os.path.isfile(ARCHIVE), "Executed archiver did not create archive.bin."
        assert os.path.isfile(LOG), "Executed archiver did not create process.log."
        assert open(ARCHIVE, 'rb').read() == expected_archive
        assert open(LOG, 'r', encoding='utf-8').read() == expected_log
        assert os.path.isfile(lock_log), "No successful fcntl archive locks were observed."
        with open(lock_log, 'r', encoding='ascii') as f:
            events = [line.strip() for line in f if line.strip()]
        assert events == ['LOCK', 'UNLOCK'] * len(expected_records), \
            "Each valid record must be surrounded by a successful F_WRLCK and F_UNLCK pair."
    finally:
        with open(WAL, 'wb') as f:
            f.write(original_wal)
        clean_outputs()
        subprocess.run([PROGRAM], check=True, timeout=15,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_archive_bin_contents():
    assert os.path.isfile(ARCHIVE), f"Archive file {ARCHIVE} was not created."
    expected_archive, _ = expected_outputs(parse_wal(WAL))
    with open(ARCHIVE, 'rb') as f:
        actual_archive = f.read()
    assert actual_archive == expected_archive, \
        f"Contents of {ARCHIVE} do not match the expected binary format."


def test_process_log_contents():
    assert os.path.isfile(LOG), f"Log file {LOG} was not created."
    _, expected_log = expected_outputs(parse_wal(WAL))
    with open(LOG, 'r', encoding='utf-8') as f:
        actual_log = f.read()
    assert actual_log == expected_log, \
        f"Contents of {LOG} do not match expected log output."


def test_source_code_uses_fcntl_locks():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with open(SOURCE, 'r', encoding='utf-8') as f:
        source_code = f.read()
    assert "fcntl" in source_code, "Source code does not contain 'fcntl' for file locking."
    assert "F_WRLCK" in source_code, "Source code does not contain 'F_WRLCK' for exclusive write locking."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
