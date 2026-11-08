#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import stat
import subprocess
import time
import pytest

ANALYSIS_PATH = "/home/user/analysis.txt"
SOURCE_PATH = "/home/user/src/service.c"
BINARY_PATH = "/home/user/service_secured"
REBUILT_PATH = "/tmp/service_rebuilt"
TRACER_PATH = "/tmp/seccomp_probe"


def test_analysis_txt_content():
    """Verify the contents of the analysis.txt file."""
    assert os.path.isfile(ANALYSIS_PATH), f"File missing: {ANALYSIS_PATH}"

    with open(ANALYSIS_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) >= 2, f"{ANALYSIS_PATH} must contain at least two lines."
    assert lines[0] == "handle_client", f"Line 1 of {ANALYSIS_PATH} is incorrect. Expected 'handle_client'."
    assert lines[1] == "128", f"Line 2 of {ANALYSIS_PATH} is incorrect. Expected '128'."


def test_service_c_patched():
    """Verify that service.c has been patched with the seccomp sandbox logic."""
    assert os.path.isfile(SOURCE_PATH), f"File missing: {SOURCE_PATH}"

    with open(SOURCE_PATH, "r") as f:
        content = f.read()

    assert "apply_sandbox" in content, "The function 'apply_sandbox' is missing in service.c."

    main_match = re.search(r'int\s+main\s*\([^)]*\)\s*\{([^}]+)', content)
    assert main_match is not None, "Could not find main() function in service.c."
    assert "apply_sandbox" in main_match.group(1), "apply_sandbox() is not called inside main()."

    assert "prctl" in content, "prctl system call is missing in service.c."
    assert "PR_SET_NO_NEW_PRIVS" in content, "PR_SET_NO_NEW_PRIVS is missing in service.c."

    has_seccomp = "SECCOMP_SET_MODE_FILTER" in content or "PR_SET_SECCOMP" in content or "seccomp_init" in content
    assert has_seccomp, "Seccomp filter installation logic is missing in service.c."

    has_execve = "59" in content or "SYS_execve" in content or "execve" in content
    has_execveat = "322" in content or "SYS_execveat" in content or "execveat" in content
    assert has_execve, "Filtering for execve (syscall 59) is missing in service.c."
    assert has_execveat, "Filtering for execveat (syscall 322) is missing in service.c."


def test_service_secured_binary_exists_and_executable():
    """Verify that the patched service is compiled and executable."""
    assert os.path.isfile(BINARY_PATH), f"Compiled binary missing: {BINARY_PATH}"
    st = os.stat(BINARY_PATH)
    is_executable = bool(st.st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH))
    assert is_executable, f"The file {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF executable."


@pytest.fixture(scope="session", autouse=True)
def build_test_artifacts():
    subprocess.run(
        ["gcc", SOURCE_PATH, "-o", REBUILT_PATH],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    tracer_source = r'''
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/reg.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

static int seccomp_mode(pid_t pid) {
    char path[64], line[256];
    snprintf(path, sizeof(path), "/proc/%ld/status", (long)pid);
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    int mode = -1;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "Seccomp:%d", &mode) == 1) break;
    }
    fclose(f);
    return mode;
}

static int finish_after_injection(pid_t child) {
    int status;
    for (;;) {
        if (waitpid(child, &status, 0) < 0) return 20;
        if (WIFSIGNALED(status))
            return WTERMSIG(status) == SIGSYS ? 0 : 21;
        if (WIFEXITED(status)) return 22;
        if (WIFSTOPPED(status)) {
            int sig = WSTOPSIG(status);
            int deliver = (sig == SIGTRAP || sig == (SIGTRAP | 0x80)) ? 0 : sig;
            if (ptrace(PTRACE_CONT, child, 0, deliver) < 0) return 23;
        }
    }
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    long target = strtol(argv[2], NULL, 10);
    if (target != SYS_execve && target != SYS_execveat) return 3;

    alarm(8);
    pid_t child = fork();
    if (child < 0) return 4;
    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, 0, 0) < 0) _exit(100);
        raise(SIGSTOP);
        execl(argv[1], argv[1], (char *)NULL);
        _exit(101);
    }

    int status;
    if (waitpid(child, &status, 0) < 0 || !WIFSTOPPED(status)) return 5;
    if (ptrace(PTRACE_SETOPTIONS, child, 0,
               PTRACE_O_TRACESYSGOOD | PTRACE_O_TRACEEXEC) < 0) return 6;
    if (ptrace(PTRACE_SYSCALL, child, 0, 0) < 0) return 7;

    int after_exec = 0;
    int in_syscall = 0;
    int waiting_for_socket_exit = 0;

    for (;;) {
        if (waitpid(child, &status, 0) < 0) return 8;
        if (WIFEXITED(status) || WIFSIGNALED(status)) return 9;
        if (!WIFSTOPPED(status)) return 10;

        int sig = WSTOPSIG(status);
        unsigned event = ((unsigned)status) >> 16;
        if (sig == SIGTRAP && event == PTRACE_EVENT_EXEC) {
            after_exec = 1;
            in_syscall = 0;
            if (ptrace(PTRACE_SYSCALL, child, 0, 0) < 0) return 11;
            continue;
        }

        if (sig == (SIGTRAP | 0x80)) {
            struct user_regs_struct regs;
            if (ptrace(PTRACE_GETREGS, child, 0, &regs) < 0) return 12;

            if (!in_syscall) {
                in_syscall = 1;
                if (after_exec && regs.orig_rax == SYS_socket) {
                    if (seccomp_mode(child) != 2) return 13;
                    waiting_for_socket_exit = 1;
                }
            } else {
                in_syscall = 0;
                if (waiting_for_socket_exit) {
                    /* Re-execute the libc syscall instruction with the forbidden
                       syscall number. This is a new syscall and therefore passes
                       through the installed seccomp filter. */
                    errno = 0;
                    long word = ptrace(PTRACE_PEEKTEXT, child,
                                       (void *)(regs.rip - 2), 0);
                    if (word == -1 && errno) return 14;
                    if ((word & 0xffff) != 0x050f) return 15;
                    regs.rip -= 2;
                    regs.rax = (unsigned long)target;
                    regs.rdi = 0;
                    regs.rsi = 0;
                    regs.rdx = 0;
                    regs.r10 = 0;
                    regs.r8 = 0;
                    regs.r9 = 0;
                    if (ptrace(PTRACE_SETREGS, child, 0, &regs) < 0) return 16;
                    if (ptrace(PTRACE_CONT, child, 0, 0) < 0) return 17;
                    return finish_after_injection(child);
                }
            }
            if (ptrace(PTRACE_SYSCALL, child, 0, 0) < 0) return 18;
            continue;
        }

        int deliver = sig == SIGTRAP ? 0 : sig;
        if (ptrace(PTRACE_SYSCALL, child, 0, deliver) < 0) return 19;
    }
}
'''
    tracer_c = "/tmp/seccomp_probe.c"
    with open(tracer_c, "w") as f:
        f.write(tracer_source)
    subprocess.run(
        ["gcc", "-O2", tracer_c, "-o", TRACER_PATH],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def assert_serves_ack(path):
    proc = subprocess.Popen(
        [path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    try:
        deadline = time.time() + 4
        last_error = None
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"{path} exited before serving traffic (status {proc.returncode})")
            try:
                with socket.create_connection(("127.0.0.1", 8888), timeout=0.3) as s:
                    s.sendall(b"hello\x00")
                    reply = s.recv(16)
                    assert reply == b"ACK\n", f"{path} did not behave as the supplied TCP service"
                    return
            except OSError as exc:
                last_error = exc
                time.sleep(0.08)
        pytest.fail(f"{path} did not listen on port 8888: {last_error}")
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=2)
        time.sleep(0.1)


def assert_forbidden_syscall_kills(path, syscall_number, name):
    result = subprocess.run(
        [TRACER_PATH, path, str(syscall_number)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{path} did not install a killing seccomp filter for {name}; "
        f"probe status={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_submitted_binary_runs_the_service():
    assert_serves_ack(BINARY_PATH)


def test_rebuilt_source_runs_the_service():
    assert_serves_ack(REBUILT_PATH)


@pytest.mark.parametrize("path", [BINARY_PATH, REBUILT_PATH])
@pytest.mark.parametrize("syscall_number,name", [(59, "execve"), (322, "execveat")])
def test_runtime_seccomp_filter(path, syscall_number, name):
    assert_forbidden_syscall_kills(path, syscall_number, name)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
