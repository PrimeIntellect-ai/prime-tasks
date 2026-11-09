#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'LAUNCHER_EOF' > /tmp/noexec_launcher.c
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>

static int blocked_syscall(long nr, int exec_count) {
    if ((nr == SYS_execve
#ifdef SYS_execveat
         || nr == SYS_execveat
#endif
        ) && exec_count >= 1) return 1;
#ifdef SYS_fork
    if (nr == SYS_fork) return 1;
#endif
#ifdef SYS_vfork
    if (nr == SYS_vfork) return 1;
#endif
#ifdef SYS_clone
    if (nr == SYS_clone) return 1;
#endif
#ifdef SYS_clone3
    if (nr == SYS_clone3) return 1;
#endif
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) return 125;

    pid_t child = fork();
    if (child < 0) return 125;
    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) == -1) _exit(125);
        raise(SIGSTOP);
        execvp(argv[1], &argv[1]);
        _exit(126);
    }

    int status;
    if (waitpid(child, &status, 0) == -1 || !WIFSTOPPED(status)) return 125;
    if (ptrace(PTRACE_SETOPTIONS, child, NULL,
               (void *)(long)(PTRACE_O_TRACESYSGOOD | PTRACE_O_EXITKILL)) == -1)
        return 125;

    bool entering = true;
    int exec_count = 0;
    if (ptrace(PTRACE_SYSCALL, child, NULL, NULL) == -1) return 125;

    for (;;) {
        if (waitpid(child, &status, 0) == -1) return 125;
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
        if (!WIFSTOPPED(status)) continue;

        int sig = WSTOPSIG(status);
        if (sig == (SIGTRAP | 0x80)) {
            if (entering) {
                errno = 0;
                long nr = ptrace(PTRACE_PEEKUSER, child,
                                 (void *)offsetof(struct user_regs_struct, orig_rax), NULL);
                if (errno) return 125;
                if (blocked_syscall(nr, exec_count)) {
                    if (ptrace(PTRACE_POKEUSER, child,
                               (void *)offsetof(struct user_regs_struct, orig_rax),
                               (void *)-1L) == -1) return 125;
                }
                if (nr == SYS_execve
#ifdef SYS_execveat
                    || nr == SYS_execveat
#endif
                ) exec_count++;
            }
            entering = !entering;
            sig = 0;
        } else if (sig == SIGTRAP || sig == SIGSTOP) {
            sig = 0;
        }

        if (ptrace(PTRACE_SYSCALL, child, NULL, (void *)(long)sig) == -1)
            return 125;
    }
}
LAUNCHER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess
import pytest

SOLUTION = "/home/user/solution.py"
ORACLE = "/app/telemetry_oracle"
LAUNCHER = "/tmp/noexec_launcher"

def test_solution_exists():
    assert os.path.exists(SOLUTION), "/home/user/solution.py does not exist."
    assert os.path.isfile(SOLUTION), "/home/user/solution.py is not a regular file."
    with open(SOLUTION, "rb") as submitted, open(ORACLE, "rb") as reference:
        assert submitted.read() != reference.read(), "Submission is byte-identical to the oracle."

def test_fuzz_equivalence():
    oracle_path = ORACLE
    agent_cmd = [LAUNCHER, "python3", SOLUTION]

    assert os.path.exists(oracle_path), f"Oracle binary {oracle_path} missing."

    random.seed(42)
    cases = []
    for i in range(100):
        num_ints = random.randint(1, 50)
        ints = [str(random.randint(2, 100000)) for _ in range(num_ints)]
        input_str = " ".join(ints) + "\n"
        input_bytes = input_str.encode("utf-8")

        try:
            oracle_proc = subprocess.run(
                [oracle_path], input=input_bytes, capture_output=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: {input_str}")

        assert oracle_proc.returncode == 0, f"Oracle failed on input: {input_str}"
        cases.append((i, input_str, input_bytes, oracle_proc.stdout))

    oracle_mode = stat.S_IMODE(os.stat(oracle_path).st_mode)
    with open(oracle_path, "rb") as f:
        oracle_bytes = f.read()
    os.unlink(oracle_path)

    try:
        for i, input_str, input_bytes, oracle_output in cases:
            try:
                agent_proc = subprocess.run(
                    agent_cmd, input=input_bytes, capture_output=True, timeout=5
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent script timed out on input: {input_str}")

            assert agent_proc.returncode == 0, (
                f"Agent script failed on input: {input_str}\n"
                f"Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
            )
            agent_output = agent_proc.stdout

            assert agent_output == oracle_output, (
                f"Mismatch on fuzz test {i+1}.\n"
                f"Input: {input_str.strip()}\n"
                f"Oracle output (hex): {oracle_output.hex()}\n"
                f"Agent output (hex): {agent_output.hex()}"
            )
    finally:
        with open(oracle_path, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(oracle_path, oracle_mode)
TEST_EOF

if gcc -O2 -Wall -Wextra -o /tmp/noexec_launcher /tmp/noexec_launcher.c && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
