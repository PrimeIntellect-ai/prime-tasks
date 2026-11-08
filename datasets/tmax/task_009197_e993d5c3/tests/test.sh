#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'PROBE_EOF' > /tmp/seccomp_probe.c
#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/syscall.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <signal.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void terminate_child(pid_t pid) {
    kill(pid, SIGKILL);
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {}
}

static int wait_until_accepting(pid_t pid) {
    for (int i = 0; i < 100; i++) {
        int status;
        pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid) return 0;

        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd >= 0) {
            struct sockaddr_in addr;
            memset(&addr, 0, sizeof(addr));
            addr.sin_family = AF_INET;
            addr.sin_port = htons(9000);
            addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
                close(fd);
                usleep(100000);
                return 1;
            }
            close(fd);
        }
        usleep(50000);
    }
    return 0;
}

int main(int argc, char **argv) {
#if !defined(__x86_64__)
    fprintf(stderr, "seccomp probe currently requires x86_64\n");
    return 2;
#else
    if (argc != 2) return 2;
    long syscall_number;
    if (strcmp(argv[1], "execve") == 0) syscall_number = __NR_execve;
    else if (strcmp(argv[1], "execveat") == 0) syscall_number = __NR_execveat;
    else return 2;

    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) {
        int nullfd = open("/dev/null", 2);
        if (nullfd >= 0) {
            dup2(nullfd, STDOUT_FILENO);
            dup2(nullfd, STDERR_FILENO);
        }
        execl("/home/user/upload_server", "/home/user/upload_server", (char *)NULL);
        _exit(127);
    }

    if (!wait_until_accepting(child)) {
        terminate_child(child);
        fprintf(stderr, "probe server did not begin accepting connections\n");
        return 1;
    }

    if (ptrace(PTRACE_ATTACH, child, NULL, NULL) < 0) {
        perror("PTRACE_ATTACH");
        terminate_child(child);
        return 1;
    }

    int status;
    if (waitpid(child, &status, 0) != child || !WIFSTOPPED(status)) {
        terminate_child(child);
        return 1;
    }

    struct user_regs_struct regs;
    if (ptrace(PTRACE_GETREGS, child, NULL, &regs) < 0) {
        perror("PTRACE_GETREGS");
        terminate_child(child);
        return 1;
    }

    errno = 0;
    long original_word = ptrace(PTRACE_PEEKTEXT, child, (void *)regs.rip, NULL);
    if (original_word == -1 && errno) {
        perror("PTRACE_PEEKTEXT");
        terminate_child(child);
        return 1;
    }

    /* Inject `syscall; int3` at the stopped instruction. If the syscall is
       allowed, execution reaches int3. KILL_PROCESS instead terminates with
       SIGSYS before the breakpoint can execute. */
    long patched_word = (original_word & ~0xFFFFFFL) | 0xCC050FL;
    if (ptrace(PTRACE_POKETEXT, child, (void *)regs.rip,
               (void *)(intptr_t)patched_word) < 0) {
        perror("PTRACE_POKETEXT");
        terminate_child(child);
        return 1;
    }

    regs.rax = syscall_number;
    regs.rdi = 1;
    regs.rsi = 1;
    regs.rdx = 1;
    regs.r10 = 1;
    regs.r8 = 1;
    regs.r9 = 1;
    if (ptrace(PTRACE_SETREGS, child, NULL, &regs) < 0 ||
        ptrace(PTRACE_CONT, child, NULL, NULL) < 0) {
        terminate_child(child);
        return 1;
    }

    if (waitpid(child, &status, 0) != child) {
        terminate_child(child);
        return 1;
    }

    if (WIFSIGNALED(status) && WTERMSIG(status) == SIGSYS) {
        return 0;
    }

    /* ALLOW, ERRNO, or TRAP did not provide the required KILL_PROCESS action. */
    terminate_child(child);
    fprintf(stderr, "%s was not killed with SIGSYS\n", argv[1]);
    return 1;
#endif
}
PROBE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import signal
import socket
import string
import subprocess
import time
import pytest


def get_server_pid(port=9000):
    try:
        output = subprocess.check_output(['ss', '-lptn'], text=True)
        for line in output.splitlines():
            if f":{port}" in line and "upload_server" in line:
                parts = line.split("pid=")
                if len(parts) > 1:
                    return int(parts[1].split(',')[0])
    except Exception:
        pass

    try:
        output = subprocess.check_output(['pgrep', '-x', 'upload_server'], text=True)
        pids = [int(p) for p in output.split()]
        if pids:
            return pids[0]
    except Exception:
        pass
    return None


def send_file(filename, content, force_hash=None, fragmented=True):
    actual_hash = hashlib.sha256(content).hexdigest()
    hash_to_send = force_hash if force_hash is not None else actual_hash
    assert len(hash_to_send) == 64
    encoded_name = filename.encode('ascii')
    assert len(encoded_name) <= 256
    payload = (hash_to_send.encode('ascii') + encoded_name.ljust(256, b'\x00') + content)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        s.connect(('127.0.0.1', 9000))
        if fragmented:
            offset = 0
            while offset < len(payload):
                chunk_size = secrets.randbelow(23) + 1
                s.sendall(payload[offset:offset + chunk_size])
                offset += chunk_size
        else:
            s.sendall(payload)
        s.shutdown(socket.SHUT_WR)
    except ConnectionRefusedError:
        pytest.fail("Connection refused. The server is not running or listening on port 9000.")
    finally:
        s.close()


def wait_for_log_lines(path, count, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(path, 'r') as f:
                lines = f.read().splitlines()
            if len(lines) >= count:
                return lines
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    with open(path, 'r') as f:
        return f.read().splitlines()


def test_upload_server_executable():
    binary_path = "/home/user/upload_server"
    assert os.path.exists(binary_path), f"Compiled binary {binary_path} does not exist."
    assert os.path.isfile(binary_path), f"{binary_path} is not a regular file."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."


def test_server_running_and_seccomp_enabled():
    pid = get_server_pid()
    assert pid is not None, "upload_server is not running or not listening on port 9000."

    status_file = f"/proc/{pid}/status"
    assert os.path.exists(status_file), f"Process status file {status_file} not found."
    with open(status_file, 'r') as f:
        status_content = f.read()

    seccomp_enabled = False
    for line in status_content.splitlines():
        if line.startswith("Seccomp:"):
            if line.split(':', 1)[1].strip() == "2":
                seccomp_enabled = True
            break
    assert seccomp_enabled, f"Seccomp filter mode is not enabled for PID {pid}. Sandboxing is missing."


def test_vulnerabilities_and_logging_with_unpredictable_inputs():
    log_file = "/home/user/server.log"
    os.makedirs('/home/user/uploads', exist_ok=True)
    open(log_file, 'w').close()

    for fixed in ('/home/user/uploads/valid_file.txt',
                  '/home/user/uploads/good_file.bin',
                  '/home/user/uploads/passwd'):
        try:
            os.remove(fixed)
        except FileNotFoundError:
            pass

    expected_logs = []

    # Preserve the original verifier cases and assertions.
    send_file("../../../etc/passwd", b"test",
              "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
    expected_logs.append("REJECTED: Path traversal attempt: ../../../etc/passwd")

    send_file("valid_file.txt", b"test", "0" * 64)
    expected_logs.append("REJECTED: Hash mismatch for valid_file.txt")

    send_file("good_file.bin", b"Secret data inside!")
    expected_logs.append("ACCEPTED: good_file.bin")

    token = secrets.token_hex(8)
    alphabet = string.ascii_letters + string.digits
    random_stem = ''.join(secrets.choice(alphabet) for _ in range(16))

    valid_cases = [
        (f"{random_stem}_{token}.dat", os.urandom(4097)),
        (f"NODOT_{token}", os.urandom(73)),
        (f"empty_{token}.bin", b""),
    ]
    for filename, content in valid_cases:
        path = os.path.join('/home/user/uploads', filename)
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
        send_file(filename, content)
        expected_logs.append(f"ACCEPTED: {filename}")

    invalid_names = [
        f"../escape_{token}",
        f"bad/{token}",
        f"bad-{token}",
        f"two.{token}.dots",
    ]
    outside_path = f"/home/user/escape_{token}"
    try:
        os.remove(outside_path)
    except FileNotFoundError:
        pass
    for filename in invalid_names:
        send_file(filename, os.urandom(91))
        expected_logs.append(f"REJECTED: Path traversal attempt: {filename}")

    mismatch_cases = []
    for _ in range(4):
        filename = f"mismatch_{secrets.token_hex(7)}.bin"
        content = os.urandom(secrets.randbelow(3000) + 1)
        actual = hashlib.sha256(content).hexdigest()
        wrong = secrets.token_hex(32)
        while wrong == actual:
            wrong = secrets.token_hex(32)
        mismatch_cases.append((filename, content, wrong))
        send_file(filename, content, wrong)
        expected_logs.append(f"REJECTED: Hash mismatch for {filename}")

    log_lines = wait_for_log_lines(log_file, len(expected_logs))
    assert log_lines == expected_logs, (
        "server.log must contain exactly one exact line per decision.\n"
        f"Expected: {expected_logs!r}\nActual: {log_lines!r}"
    )

    saved_file = "/home/user/uploads/good_file.bin"
    assert os.path.exists(saved_file), f"Valid file was not saved to {saved_file}."
    with open(saved_file, 'rb') as f:
        assert f.read() == b"Secret data inside!", f"Content of {saved_file} does not match the sent payload."

    assert not os.path.exists("/home/user/uploads/valid_file.txt"), "File with mismatched hash was saved."
    assert not os.path.exists("/home/user/uploads/passwd"), "Path traversal file was partially saved."

    for filename, content in valid_cases:
        path = os.path.join('/home/user/uploads', filename)
        assert os.path.isfile(path), f"Valid randomized upload was not saved: {path}"
        with open(path, 'rb') as f:
            assert f.read() == content, f"Randomized payload was corrupted for {filename}"

    assert not os.path.exists(outside_path), "Traversal upload escaped the uploads directory."
    for filename, _, _ in mismatch_cases:
        assert not os.path.exists(os.path.join('/home/user/uploads', filename)), (
            f"Hash-mismatched randomized upload was saved: {filename}"
        )


def test_z_execve_and_execveat_are_kill_process_actions():
    # Stop the agent-started instance so separately launched copies can bind.
    subprocess.run(['pkill', '-TERM', '-x', 'upload_server'], check=False)
    time.sleep(0.3)
    subprocess.run(['pkill', '-KILL', '-x', 'upload_server'], check=False)
    time.sleep(0.2)

    for syscall_name in ('execve', 'execveat'):
        result = subprocess.run(
            ['/tmp/seccomp_probe', syscall_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"The installed seccomp filter did not kill {syscall_name} with SIGSYS. "
            f"Probe output: {result.stdout}{result.stderr}"
        )
        time.sleep(0.15)
TEST_EOF

gcc /tmp/seccomp_probe.c -o /tmp/seccomp_probe >/tmp/probe_build.log 2>&1
compile_status=$?
if [ "$compile_status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
    test_status=$?
else
    cat /tmp/probe_build.log
    test_status=1
fi

if [ "$test_status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
