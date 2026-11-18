#!/bin/bash
set +e
mkdir -p /logs/verifier

cat > /tmp/chunk_guard.c <<'GUARD_EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <sys/sendfile.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <unistd.h>

static void mark(char c) {
    int fd = (int)syscall(SYS_openat, AT_FDCWD, "/tmp/backup_chunk_guard.log", O_WRONLY|O_CREAT|O_APPEND, 0666);
    if (fd >= 0) {
        syscall(SYS_write, fd, &c, 1);
        syscall(SYS_close, fd);
    }
}

static int is_socket_fd(int fd) {
    int type = 0;
    socklen_t len = sizeof(type);
    return getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &len) == 0;
}

static void check_count(int fd, size_t count) {
    if (count > 1024 && is_socket_fd(fd)) mark('V');
}

__attribute__((constructor)) static void loaded(void) { mark('L'); }

ssize_t send(int fd, const void *buf, size_t len, int flags) {
    static ssize_t (*real_fn)(int,const void*,size_t,int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "send");
    check_count(fd, len);
    return real_fn(fd, buf, len, flags);
}

ssize_t sendto(int fd, const void *buf, size_t len, int flags,
               const struct sockaddr *addr, socklen_t alen) {
    static ssize_t (*real_fn)(int,const void*,size_t,int,const struct sockaddr*,socklen_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sendto");
    check_count(fd, len);
    return real_fn(fd, buf, len, flags, addr, alen);
}

ssize_t write(int fd, const void *buf, size_t len) {
    static ssize_t (*real_fn)(int,const void*,size_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "write");
    check_count(fd, len);
    return real_fn(fd, buf, len);
}

ssize_t writev(int fd, const struct iovec *iov, int n) {
    static ssize_t (*real_fn)(int,const struct iovec*,int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "writev");
    size_t total = 0;
    for (int i = 0; i < n; i++) total += iov[i].iov_len;
    check_count(fd, total);
    return real_fn(fd, iov, n);
}

ssize_t sendmsg(int fd, const struct msghdr *msg, int flags) {
    static ssize_t (*real_fn)(int,const struct msghdr*,int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sendmsg");
    size_t total = 0;
    for (size_t i = 0; i < msg->msg_iovlen; i++) total += msg->msg_iov[i].iov_len;
    check_count(fd, total);
    return real_fn(fd, msg, flags);
}

ssize_t sendfile(int out_fd, int in_fd, off_t *off, size_t count) {
    static ssize_t (*real_fn)(int,int,off_t*,size_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sendfile");
    check_count(out_fd, count);
    return real_fn(out_fd, in_fd, off, count);
}
GUARD_EOF

gcc -shared -fPIC -O2 -o /tmp/chunk_guard.so /tmp/chunk_guard.c -ldl
if [ $? -ne 0 ]; then
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

cat > /tmp/test_backup_daemon.py <<'PY_EOF'
import fcntl
import os
import signal
import socket
import stat
import struct
import subprocess
import time
import uuid

HOST = "127.0.0.1"
PORT = 9090
BINARY = "/home/user/backup_daemon"
ROOT = "/home/user/live_data"
GUARD_LOG = "/tmp/backup_chunk_guard.log"


def assert_artifacts():
    st = os.lstat(BINARY)
    assert stat.S_ISREG(st.st_mode), "backup_daemon is not a regular compiled binary"
    assert os.access(BINARY, os.X_OK), "backup_daemon is not executable"
    with open(BINARY, "rb") as f:
        hdr = f.read(20)
    assert hdr[:4] == b"\x7fELF", "backup_daemon is not an ELF binary"
    assert len(hdr) >= 18 and hdr[5] in (1, 2), "invalid ELF header"
    endian = "little" if hdr[5] == 1 else "big"
    assert int.from_bytes(hdr[16:18], endian) in (2, 3), "ELF is not an executable/shared executable"

    sources = []
    for base, dirs, files in os.walk("/home/user"):
        for name in files:
            if name.endswith(".c"):
                path = os.path.join(base, name)
                try:
                    sources.append(open(path, "r", errors="ignore").read())
                except OSError:
                    pass
    assert sources, "no C source implementation was left under /home/user"
    joined = "\n".join(sources)
    for token in ("socket", "bind", "listen", "accept"):
        assert token in joined, f"C source does not contain required networking operation: {token}"


def listening_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":2382") and fields[3] == "0A":
                inodes.add(fields[9])
    result = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    target = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(pid))
        except OSError:
            pass
    return result


def wait_listener(timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pids = listening_pids()
        if pids:
            return pids
        time.sleep(0.05)
    raise AssertionError("daemon did not listen on 127.0.0.1:9090")


def check_listener_binary(pids):
    expected = os.path.realpath(BINARY)
    for pid in pids:
        try:
            actual = os.path.realpath(f"/proc/{pid}/exe")
        except OSError:
            continue
        assert actual == expected, f"port 9090 is served by {actual}, not {expected}"


def restart_instrumented():
    old = listening_pids()
    assert old, "no running daemon found on port 9090"
    check_listener_binary(old)
    for pid in old:
        try: os.kill(pid, signal.SIGTERM)
        except ProcessLookupError: pass
    time.sleep(0.3)
    for pid in listening_pids():
        try: os.kill(pid, signal.SIGKILL)
        except ProcessLookupError: pass
    deadline = time.time() + 3
    while listening_pids() and time.time() < deadline:
        time.sleep(0.05)
    assert not listening_pids(), "could not stop original daemon for instrumentation"

    try: os.unlink(GUARD_LOG)
    except FileNotFoundError: pass
    env = os.environ.copy()
    env["LD_PRELOAD"] = "/tmp/chunk_guard.so"
    subprocess.Popen([BINARY], env=env, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    pids = wait_listener()
    check_listener_binary(pids)
    deadline = time.time() + 2
    while time.time() < deadline:
        try:
            if b"L" in open(GUARD_LOG, "rb").read():
                return
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    raise AssertionError("compiled daemon could not be instrumented to verify transmission chunking")


def add_dynamic_fixtures():
    tag = uuid.uuid4().hex
    nested = os.path.join(ROOT, "verify_" + tag, "nested")
    os.makedirs(nested)
    small = os.urandom(137)
    large = os.urandom(1024 * 6 + 333)
    small_path = os.path.join(nested, "small_" + tag + ".bin")
    large_path = os.path.join(nested, "large_" + tag + ".bin")
    with open(small_path, "wb") as f: f.write(small)
    with open(large_path, "wb") as f: f.write(large)
    os.symlink(large_path, os.path.join(ROOT, "resolved_" + tag + ".link"))
    os.symlink(os.path.join(ROOT, "missing_" + tag), os.path.join(ROOT, "dangling_" + tag))


def expected_files():
    result = {}
    def visit(directory):
        for entry in os.scandir(directory):
            rel = os.path.relpath(entry.path, ROOT).replace(os.sep, "/")
            if entry.is_symlink():
                try:
                    target_st = os.stat(entry.path)
                except (OSError, RuntimeError):
                    continue
                if stat.S_ISREG(target_st.st_mode):
                    with open(entry.path, "rb") as f: result[rel] = f.read()
            elif entry.is_dir(follow_symlinks=False):
                visit(entry.path)
            elif entry.is_file(follow_symlinks=False):
                with open(entry.path, "rb") as f: result[rel] = f.read()
    visit(ROOT)
    return result


def recv_exact(sock, n):
    data = bytearray()
    while len(data) < n:
        part = sock.recv(n - len(data))
        assert part, "connection closed unexpectedly before end marker"
        data.extend(part)
    return bytes(data)


def bad_auth_test():
    with socket.create_connection((HOST, PORT), timeout=5) as s:
        s.settimeout(2)
        s.sendall(b"AUTH: wrong password\n")
        try:
            data = s.recv(1024)
            assert data == b"", "server returned data for invalid authentication"
        except ConnectionResetError:
            pass
        except socket.timeout:
            raise AssertionError("server did not immediately close invalid-auth connection")


def backup_and_lock_test(expected):
    lockfd = os.open("/tmp/backup.lock", os.O_RDWR | os.O_CREAT, 0o666)
    fcntl.flock(lockfd, fcntl.LOCK_EX)
    try:
        s = socket.create_connection((HOST, PORT), timeout=5)
        s.sendall(b"AUTH: gamma ray burst\n")
        s.sendall(b"BACKUP\n")
        s.settimeout(0.5)
        try:
            first = s.recv(1)
            assert False, f"daemon streamed before acquiring /tmp/backup.lock: {first!r}"
        except socket.timeout:
            pass
        fcntl.flock(lockfd, fcntl.LOCK_UN)
    finally:
        os.close(lockfd)

    received = {}
    s.settimeout(8)
    with s:
        while True:
            plen = struct.unpack("<H", recv_exact(s, 2))[0]
            if plen == 0:
                break
            path_raw = recv_exact(s, plen)
            path = path_raw.decode("utf-8")
            assert path not in received, f"duplicate path in stream: {path}"
            assert not path.startswith("/") and ".." not in path.split("/"), f"non-relative path: {path}"
            size = struct.unpack("<I", recv_exact(s, 4))[0]
            assert size < 100_000_000, "unreasonable streamed file size"
            received[path] = recv_exact(s, size) if size else b""
        try:
            trailing = s.recv(1)
            assert trailing == b"", "daemon did not close connection after end marker"
        except socket.timeout:
            raise AssertionError("daemon did not close connection after end marker")

    assert received == expected, (
        f"backup differs from live traversal; missing={sorted(set(expected)-set(received))}, "
        f"extra={sorted(set(received)-set(expected))}, "
        f"wrong_data={sorted(k for k in set(expected)&set(received) if expected[k] != received[k])}"
    )
    assert received.get("file1.txt") == b"Important data 1\n"
    assert received.get("folder1/file2.txt") == b"Important data 2\n"

    guard = open(GUARD_LOG, "rb").read()
    assert b"L" in guard, "chunk guard was not loaded"
    assert b"V" not in guard, "daemon made a socket transmission larger than the required 1024 bytes"


def main():
    assert_artifacts()
    add_dynamic_fixtures()
    expected = expected_files()
    assert any(len(v) > 1024 for v in expected.values()), "large dynamic fixture missing"
    restart_instrumented()
    bad_auth_test()
    backup_and_lock_test(expected)


if __name__ == "__main__":
    main()
PY_EOF

python3 /tmp/test_backup_daemon.py
status=$?
if [ $status -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
