#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACER_EOF' > /tmp/noexec_tracer.c
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

static int prohibited(long nr) {
    if (nr == SYS_execve || nr == SYS_fork || nr == SYS_vfork || nr == SYS_clone)
        return 1;
#ifdef SYS_execveat
    if (nr == SYS_execveat)
        return 1;
#endif
#ifdef SYS_clone3
    if (nr == SYS_clone3)
        return 1;
#endif
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) return 125;

    pid_t child = fork();
    if (child < 0) return 125;
    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) < 0) _exit(125);
        raise(SIGSTOP);
        execl(argv[1], argv[1], (char *)NULL);
        _exit(127);
    }

    int status;
    if (waitpid(child, &status, 0) < 0 || !WIFSTOPPED(status)) return 125;
    if (ptrace(PTRACE_SETOPTIONS, child, 0,
               PTRACE_O_TRACESYSGOOD | PTRACE_O_TRACEEXEC | PTRACE_O_EXITKILL) < 0)
        return 125;
    if (ptrace(PTRACE_SYSCALL, child, 0, 0) < 0) return 125;

    int in_syscall = 0;
    int initial_exec_complete = 0;

    for (;;) {
        if (waitpid(child, &status, 0) < 0) return 125;
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
        if (!WIFSTOPPED(status)) continue;

        int sig = WSTOPSIG(status);
        unsigned int event = (unsigned int)status >> 16;

        if (sig == SIGTRAP && event == PTRACE_EVENT_EXEC) {
            initial_exec_complete = 1;
        } else if (sig == (SIGTRAP | 0x80)) {
            if (!in_syscall) {
                struct user_regs_struct regs;
                if (ptrace(PTRACE_GETREGS, child, 0, &regs) < 0) return 125;
                if (initial_exec_complete && prohibited((long)regs.orig_rax)) {
                    ptrace(PTRACE_KILL, child, 0, 0);
                    waitpid(child, &status, 0);
                    return 126;
                }
            }
            in_syscall = !in_syscall;
        }

        int deliver = 0;
        if (sig != (SIGTRAP | 0x80) && sig != SIGTRAP && sig != SIGSTOP)
            deliver = sig;
        if (ptrace(PTRACE_SYSCALL, child, 0, deliver) < 0) return 125;
    }
}
TRACER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/ws_oracle"
SOURCE_PATH = "/home/user/src/parser.c"
AGENT_PATH = "/home/user/bin/parser"
TRACER_PATH = "/tmp/noexec_tracer"
NUM_ITERATIONS = 10000


def generate_valid_frame():
    opcode = random.choice([1, 8])
    fin = random.choice([0, 0x80])
    byte0 = fin | opcode

    mask = random.choice([0, 0x80])
    payload_len = random.randint(0, 125)
    byte1 = mask | payload_len

    frame = bytearray([byte0, byte1])
    if mask:
        frame.extend(random.randint(0, 255) for _ in range(4))
    frame.extend(random.randint(0, 255) for _ in range(payload_len))
    return bytes(frame)


def generate_valid_frames_input():
    data = bytearray()
    for _ in range(random.randint(1, 10)):
        data.extend(generate_valid_frame())
    return bytes(data)


def generate_random_noise():
    return bytes(random.randint(0, 255) for _ in range(random.randint(1, 1024)))


def test_fuzz_equivalence():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary is not executable: {AGENT_PATH}"
    assert stat.S_ISREG(os.lstat(AGENT_PATH).st_mode), "Agent binary must be a regular file, not a symlink"
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), "C source must be a regular file"
    assert os.path.isfile(ORACLE_PATH) and os.access(ORACLE_PATH, os.X_OK)

    with open(AGENT_PATH, "rb") as submitted, open(ORACLE_PATH, "rb") as oracle:
        assert submitted.read() != oracle.read(), "Submitted executable is a copy of the oracle"

    tracer_build = subprocess.run(
        ["gcc", "-O2", "/tmp/noexec_tracer.c", "-o", TRACER_PATH],
        capture_output=True,
        text=True,
    )
    assert tracer_build.returncode == 0, tracer_build.stderr

    compiled_path = AGENT_PATH + ".verified"
    compile_proc = subprocess.run(
        ["gcc", "-O2", SOURCE_PATH, "-o", compiled_path],
        capture_output=True,
        text=True,
    )
    assert compile_proc.returncode == 0, f"parser.c failed to compile with GCC:\n{compile_proc.stderr}"
    assert os.path.isfile(compiled_path) and os.access(compiled_path, os.X_OK)
    with open(compiled_path, "rb") as compiled:
        assert compiled.read(4) == b"\x7fELF", "Compiled parser is not an ELF executable"
    os.replace(compiled_path, AGENT_PATH)

    random.seed(42)
    cases = []
    for _ in range(NUM_ITERATIONS):
        if random.random() < 0.5:
            input_data = generate_valid_frames_input()
        else:
            input_data = generate_random_noise()
        if len(input_data) > 1024:
            input_data = input_data[:1024]
        if len(input_data) == 0:
            input_data = b"\x00"
        cases.append(input_data)

    expected = []
    for input_data in cases:
        proc = subprocess.run([ORACLE_PATH], input=input_data, capture_output=True)
        expected.append((proc.returncode, proc.stdout))

    hidden_dir = tempfile.mkdtemp(prefix="ws_reference_")
    hidden_oracle = os.path.join(hidden_dir, "reference")
    os.rename(ORACLE_PATH, hidden_oracle)
    try:
        for i, input_data in enumerate(cases):
            oracle_returncode, oracle_stdout = expected[i]
            agent_proc = subprocess.run(
                [TRACER_PATH, AGENT_PATH], input=input_data, capture_output=True
            )
            if agent_proc.returncode != oracle_returncode or agent_proc.stdout != oracle_stdout:
                pytest.fail(
                    f"Mismatch on iteration {i} with input {input_data.hex()}.\n"
                    f"Oracle returncode: {oracle_returncode}, Agent returncode: {agent_proc.returncode}\n"
                    f"Oracle stdout: {oracle_stdout!r}\n"
                    f"Agent stdout: {agent_proc.stdout!r}"
                )
    finally:
        os.rename(hidden_oracle, ORACLE_PATH)
        os.rmdir(hidden_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
