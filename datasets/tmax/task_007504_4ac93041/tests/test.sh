#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import secrets
import signal
import socket
import subprocess
import time


def get_md5(file_path):
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def listener_address(pid, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not os.path.exists(f"/proc/{pid}"):
            return None
        inodes = set()
        for fd in glob.glob(f"/proc/{pid}/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("socket:["):
                inodes.add(target[8:-1])
        try:
            with open("/proc/net/tcp") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local, state, inode = fields[1], fields[3], fields[9]
                    address, port = local.split(":")
                    if inode in inodes and state == "0A" and port.upper() == "1F90":
                        return address
        except OSError:
            pass
        time.sleep(0.05)
    return None


def stop_process(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def test_cpp_fixed():
    path = "/home/user/restore_daemon.cpp"
    assert os.path.exists(path), f"{path} missing"
    with open(path, "r") as f:
        content = f.read()
    assert "INADDR_ANY" in content, "C++ code not modified to use INADDR_ANY"
    assert "INADDR_LOOPBACK" not in content, "C++ code still contains INADDR_LOOPBACK"


def test_binary_compiled():
    path = "/home/user/restore_daemon"
    assert os.path.exists(path), f"{path} missing"
    assert os.access(path, os.X_OK), f"{path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary"

    built = subprocess.run(
        ["g++", "-std=c++11", "/home/user/restore_daemon.cpp", "-o", "/tmp/verifier_source_build"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert built.returncode == 0, f"restore_daemon.cpp does not compile:\n{built.stderr}"


def test_daemon_network_behavior():
    binary = "/home/user/restore_daemon"
    restored = "/home/user/restored_data.bin"
    try:
        os.remove(restored)
    except FileNotFoundError:
        pass

    crash_proc = subprocess.Popen([binary], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        address = listener_address(crash_proc.pid)
        assert address is not None, "daemon did not listen on TCP port 8080"
        assert address == "00000000", "daemon is not bound to all IPv4 interfaces"
        with socket.create_connection(("127.0.0.1", 8080), timeout=3) as conn:
            conn.sendall(b"CRASH_TEST")
            conn.shutdown(socket.SHUT_WR)
        crash_status = crash_proc.wait(timeout=5)
        assert crash_status != 0, "daemon did not exit non-zero after CRASH_TEST"
    finally:
        stop_process(crash_proc)

    payload = b"VERIFIER_RESTORE_PAYLOAD\n" + secrets.token_bytes(262144)
    restore_proc = subprocess.Popen([binary], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        address = listener_address(restore_proc.pid)
        assert address == "00000000", "restarted daemon is not bound to all IPv4 interfaces"
        with socket.create_connection(("127.0.0.1", 8080), timeout=3) as conn:
            conn.sendall(payload)
            conn.shutdown(socket.SHUT_WR)
        status = restore_proc.wait(timeout=10)
        assert status == 0, f"daemon exited with {status} while restoring ordinary data"
    finally:
        stop_process(restore_proc)

    assert os.path.exists(restored), "daemon did not create restored_data.bin"
    with open(restored, "rb") as f:
        assert f.read() == payload, "daemon did not restore the bytes received over TCP"


def test_pipeline_script_and_execution():
    script = "/home/user/pipeline.sh"
    binary = "/home/user/restore_daemon"
    real_binary = "/tmp/verifier_restore_daemon.real"
    event_log = "/tmp/verifier_daemon_events.log"
    preload_src = "/tmp/verifier_capture.c"
    preload_so = "/tmp/verifier_capture.so"
    backup = "/home/user/backup_archive.tar.gz"
    restored = "/home/user/restored_data.bin"
    result = "/home/user/pipeline_result.log"

    assert os.path.exists(script), f"{script} missing"
    assert os.access(script, os.X_OK), f"{script} is not executable"

    capture_code = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdio.h>

ssize_t read(int fd, void *buf, size_t count) {
    static ssize_t (*real_read)(int, void *, size_t) = 0;
    if (!real_read) real_read = dlsym(RTLD_NEXT, "read");
    ssize_t n = real_read(fd, buf, count);
    if (n > 0) {
        struct sockaddr_in addr;
        socklen_t len = sizeof(addr);
        if (getsockname(fd, (struct sockaddr *)&addr, &len) == 0 &&
            addr.sin_family == AF_INET && ntohs(addr.sin_port) == 8080) {
            char path[128];
            snprintf(path, sizeof(path), "/tmp/verifier_net_%ld", (long)getpid());
            int out = syscall(SYS_openat, AT_FDCWD, path, O_WRONLY|O_CREAT|O_APPEND, 0600);
            if (out >= 0) {
                syscall(SYS_write, out, buf, (size_t)n);
                syscall(SYS_close, out);
            }
        }
    }
    return n;
}
'''
    with open(preload_src, "w") as f:
        f.write(capture_code)
    compiled = subprocess.run(
        ["gcc", "-shared", "-fPIC", preload_src, "-o", preload_so, "-ldl"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert compiled.returncode == 0, f"failed to build verifier instrumentation: {compiled.stderr}"

    for path in glob.glob("/tmp/verifier_net_*") + [event_log]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    payload = b"PIPELINE_DYNAMIC_BACKUP\n" + secrets.token_bytes(1048576 - 24)
    with open(backup, "wb") as f:
        f.write(payload)
    for path in (restored, result):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    os.replace(binary, real_binary)
    wrapper = f'''#!/bin/bash
echo "START $$" >> {event_log}
LD_PRELOAD={preload_so} {real_binary}
rc=$?
echo "EXIT $$ $rc" >> {event_log}
exit $rc
'''
    with open(binary, "w") as f:
        f.write(wrapper)
    os.chmod(binary, 0o755)

    proc = None
    try:
        proc = subprocess.Popen(
            ["/bin/bash", script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            stdout, stderr = proc.communicate(timeout=90)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            stdout, stderr = proc.communicate()
            raise AssertionError(f"pipeline timed out\nstdout:\n{stdout}\nstderr:\n{stderr}")
        assert proc.returncode == 0, (
            f"pipeline exited with {proc.returncode}\nstdout:\n{stdout}\nstderr:\n{stderr}"
        )
    finally:
        if proc is not None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if os.path.exists(real_binary):
            try:
                os.remove(binary)
            except FileNotFoundError:
                pass
            os.replace(real_binary, binary)

    assert os.path.exists(event_log), "pipeline never launched /home/user/restore_daemon"
    with open(event_log) as f:
        events = [line.strip().split() for line in f if line.strip()]

    crash_indexes = [i for i, e in enumerate(events) if len(e) == 3 and e[0] == "EXIT" and e[2] != "0"]
    success_indexes = [i for i, e in enumerate(events) if len(e) == 3 and e[0] == "EXIT" and e[2] == "0"]
    assert crash_indexes, "pipeline did not supervise a daemon crash"
    crash_index = crash_indexes[0]
    assert any(i > crash_index and e[0] == "START" for i, e in enumerate(events)), (
        "supervisor did not restart the daemon after its non-zero exit"
    )
    assert any(i > crash_index for i in success_indexes), (
        "restarted daemon did not later exit successfully"
    )

    network_inputs = []
    for path in glob.glob("/tmp/verifier_net_*"):
        with open(path, "rb") as f:
            network_inputs.append(f.read())
    assert b"CRASH_TEST" in network_inputs, "pipeline did not send CRASH_TEST to the daemon over TCP"
    assert payload in network_inputs, "pipeline did not send the backup contents to the daemon over TCP"


def test_restored_data():
    orig = "/home/user/backup_archive.tar.gz"
    restored = "/home/user/restored_data.bin"
    assert os.path.exists(restored), f"{restored} missing"
    assert get_md5(orig) == get_md5(restored), "Restored data does not match backup archive"


def test_pipeline_result():
    path = "/home/user/pipeline_result.log"
    assert os.path.exists(path), f"{path} missing"
    with open(path, "r") as f:
        content = f.read().strip()
    assert "PIPELINE SUCCESS" in content, f"Expected PIPELINE SUCCESS in {path}"
    assert content == "PIPELINE SUCCESS", f"Expected exact PIPELINE SUCCESS in {path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
