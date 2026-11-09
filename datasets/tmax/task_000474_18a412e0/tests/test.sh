#!/bin/bash
set -e
mkdir -p /logs/verifier

cat > /tmp/audit_trace.c <<'C_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <unistd.h>

static void mark(char c) {
    int fd = syscall(SYS_openat, AT_FDCWD, "/tmp/audit_trace.log", O_WRONLY|O_CREAT|O_APPEND, 0666);
    if (fd >= 0) { syscall(SYS_write, fd, &c, 1); syscall(SYS_close, fd); }
}
static void mark_path(const char *p) {
    if (p && strstr(p, "/home/user/backup_logs")) mark('G');
}

int open(const char *p, int flags, ...) {
    static int (*real_fn)(const char*,int,...) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap); }
    mark_path(p);
    return (flags & O_CREAT) ? real_fn(p, flags, mode) : real_fn(p, flags);
}
int open64(const char *p, int flags, ...) {
    static int (*real_fn)(const char*,int,...) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "open64");
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap); }
    mark_path(p);
    return (flags & O_CREAT) ? real_fn(p, flags, mode) : real_fn(p, flags);
}
int openat(int d, const char *p, int flags, ...) {
    static int (*real_fn)(int,const char*,int,...) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "openat");
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list ap; va_start(ap, flags); mode = va_arg(ap, int); va_end(ap); }
    mark_path(p);
    return (flags & O_CREAT) ? real_fn(d, p, flags, mode) : real_fn(d, p, flags);
}
FILE *fopen(const char *p, const char *m) {
    static FILE *(*real_fn)(const char*,const char*) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "fopen");
    mark_path(p);
    return real_fn(p, m);
}
int flock(int fd, int op) {
    static int (*real_fn)(int,int) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "flock");
    if (op & LOCK_EX) mark('L');
    return real_fn(fd, op);
}
int fcntl(int fd, int cmd, ...) {
    static int (*real_fn)(int,int,...) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "fcntl");
    if (cmd == F_GETFD || cmd == F_GETFL || cmd == F_GETOWN) return real_fn(fd, cmd);
    va_list ap; va_start(ap, cmd); void *arg = va_arg(ap, void*); va_end(ap);
    if ((cmd == F_SETLK || cmd == F_SETLKW) && arg && ((struct flock*)arg)->l_type == F_WRLCK) mark('L');
    return real_fn(fd, cmd, arg);
}
C_EOF
gcc -shared -fPIC -o /tmp/audit_trace.so /tmp/audit_trace.c -ldl
: > /tmp/audit_trace.log
chmod 666 /tmp/audit_trace.log

cat > /tmp/test_final_state.py <<'PY_EOF'
import os
import re
import shutil
import socket
import subprocess
import tarfile
import tempfile
import threading
import time
import uuid

import cv2
import numpy as np

HOST = "127.0.0.1"
PORT = 9090
SERVER = "/home/user/audit_server"
TRACE = "/tmp/audit_trace.log"


def send_request(command):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5)
        s.connect((HOST, PORT))
        s.sendall(command.encode())
        data = b""
        while b"\n" not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return data.decode()


def wait_server():
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            send_request("GET_CORRUPTED\n")
            return
        except OSError:
            time.sleep(0.1)
    raise AssertionError("audit server did not listen on 127.0.0.1:9090")


def derive_corrupted():
    bad = []
    for root, _, files in os.walk("/home/user/backups"):
        for name in files:
            if name.endswith(".tar.gz"):
                path = os.path.join(root, name)
                result = subprocess.run(["tar", "-tzf", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if result.returncode != 0:
                    bad.append(name)
    assert len(bad) == 1, f"test fixture must contain one corrupt archive, got {bad}"
    return bad[0]


def derive_token(path="/app/backup_audit.mp4"):
    cap = cv2.VideoCapture(path)
    assert cap.isOpened()
    bits = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        h, w = frame.shape[:2]
        bits.append("1" if int(frame[h // 2, w // 2].mean()) >= 128 else "0")
    cap.release()
    assert bits and len(bits) % 8 == 0
    return "".join(chr(int("".join(bits[i:i+8]), 2)) for i in range(0, len(bits), 8))


def derive_success_ids():
    found = []
    record_re = re.compile(r"\[START_BACKUP\](.*?)\[END_BACKUP\]", re.S)
    for root, _, files in os.walk("/home/user/backup_logs"):
        for name in files:
            with open(os.path.join(root, name), errors="replace") as f:
                for record in record_re.findall(f.read()):
                    mid = re.search(r"^ID:\s*(.+?)\s*$", record, re.M)
                    status = re.search(r"^STATUS:\s*(SUCCESS|FAILED)\s*$", record, re.M)
                    if mid and status and status.group(1) == "SUCCESS":
                        found.append(mid.group(1))
    return found


def find_cpp_source():
    candidates = []
    for base in ("/home/user", "/app"):
        for root, _, files in os.walk(base):
            for name in files:
                if name.endswith((".cpp", ".cc", ".cxx", ".C")):
                    candidates.append(os.path.join(root, name))
    assert candidates, "C++ server source was not left in the requested workspace"
    texts = []
    for path in candidates:
        with open(path, errors="replace") as f:
            texts.append(f.read())
    combined = "\n".join(texts)
    assert "GET_CORRUPTED" in combined and "GET_TOKEN" in combined and "RECORD_ACCESS" in combined
    assert re.search(r"\b(flock|fcntl)\s*\(", combined), "C++ source does not invoke flock/fcntl"
    for token in ("START_BACKUP", "ID", "STATUS", "SUCCESS"):
        assert token in combined, f"C++ implementation has no backup-log parsing for {token}"


def test_original_server_and_artifact():
    assert os.path.isfile(SERVER) and os.access(SERVER, os.X_OK)
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_server is not a compiled executable"
    find_cpp_source()
    assert derive_success_ids() == ["BKP-992", "BKP-993"]
    assert send_request("GET_CORRUPTED\n").strip() == derive_corrupted()
    assert send_request("GET_TOKEN\n").strip() == derive_token()


def install_random_challenge():
    shutil.rmtree("/home/user/backups")
    os.makedirs("/home/user/backups/deep/monthly")
    corrupt_name = "damaged_" + uuid.uuid4().hex + ".tar.gz"
    for i in range(3):
        path = f"/home/user/backups/deep/monthly/valid_{uuid.uuid4().hex}.tar.gz"
        with tempfile.TemporaryDirectory() as td:
            payload = os.path.join(td, "payload")
            with open(payload, "wb") as f:
                f.write(os.urandom(128 + i))
            with tarfile.open(path, "w:gz") as tf:
                tf.add(payload, arcname="payload")
    bad_path = os.path.join("/home/user/backups", corrupt_name)
    with open(bad_path, "wb") as f:
        f.write(os.urandom(257))

    token = ("T" + uuid.uuid4().hex[:8]).upper()
    bits = "".join(f"{ord(c):08b}" for c in token)
    out = cv2.VideoWriter("/app/backup_audit.mp4", cv2.VideoWriter_fourcc(*"mp4v"), 10, (100, 100))
    assert out.isOpened()
    for bit in bits:
        out.write(np.full((100, 100, 3), 255 if bit == "1" else 0, dtype=np.uint8))
    out.release()

    ids = ["OK-" + uuid.uuid4().hex, "OK-" + uuid.uuid4().hex]
    failed = "BAD-" + uuid.uuid4().hex
    os.makedirs("/home/user/backup_logs", exist_ok=True)
    for name in os.listdir("/home/user/backup_logs"):
        os.remove(os.path.join("/home/user/backup_logs", name))
    with open("/home/user/backup_logs/random.log", "w") as f:
        for ident, status in ((ids[0], "SUCCESS"), (failed, "FAILED"), (ids[1], "SUCCESS")):
            f.write(f"[START_BACKUP]\nID: {ident}\nTIMESTAMP: 1700000000\nSTATUS: {status}\n[END_BACKUP]\n")
    assert derive_success_ids() == ids
    return corrupt_name, token


def restart_instrumented_server():
    subprocess.run(["pkill", "-x", "audit_server"], check=False)
    time.sleep(0.3)
    open(TRACE, "w").close()
    env = os.environ.copy()
    env["LD_PRELOAD"] = "/tmp/audit_trace.so"
    subprocess.Popen([SERVER], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    wait_server()


def test_randomized_inputs_and_locking():
    expected_bad, expected_token = install_random_challenge()
    restart_instrumented_server()
    assert derive_corrupted() == expected_bad
    assert derive_token() == expected_token
    assert send_request("GET_CORRUPTED\n").strip() == expected_bad
    assert send_request("GET_TOKEN\n").strip() == expected_token

    log_path = "/home/user/access.log"
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass
    entries = ["test_entry_" + uuid.uuid4().hex for _ in range(20)]
    responses, errors = [], []
    def worker(entry):
        try:
            responses.append(send_request("RECORD_ACCESS " + entry + "\n"))
        except Exception as exc:
            errors.append(exc)
    threads = [threading.Thread(target=worker, args=(entry,)) for entry in entries]
    for thread in threads: thread.start()
    for thread in threads: thread.join()
    assert not errors, errors
    assert len(responses) == len(entries)
    assert all(response.strip() == "OK" for response in responses)
    assert os.path.isfile(log_path)
    with open(log_path) as f:
        lines = [line for line in f.read().splitlines() if line.strip()]
    assert len(lines) == len(entries)
    assert set(lines) == set(entries)
    with open(TRACE) as f:
        trace = f.read()
    assert "L" in trace, "no exclusive flock/fcntl operation occurred around RECORD_ACCESS writes"
    assert "G" in trace, "the restarted server did not read the randomized backup logs"
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
