#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove any helper process the agent may have left running to proxy the legacy
# executable during verification.
pkill -KILL -u user 2>/dev/null || true

cat << 'TRACE_EOF' > /tmp/noexec_trace.c
#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) return 126;

    pid_t root = fork();
    if (root < 0) return 126;

    if (root == 0) {
        setpgid(0, 0);
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) < 0) _exit(126);
        raise(SIGSTOP);
        execv(argv[1], &argv[1]);
        _exit(127);
    }

    int status;
    if (waitpid(root, &status, 0) != root || !WIFSTOPPED(status)) {
        return 126;
    }

    unsigned long options = PTRACE_O_TRACEEXEC |
                            PTRACE_O_TRACEFORK |
                            PTRACE_O_TRACEVFORK |
                            PTRACE_O_TRACECLONE |
                            PTRACE_O_EXITKILL;
    if (ptrace(PTRACE_SETOPTIONS, root, NULL, (void *)options) < 0) {
        kill(-root, SIGKILL);
        return 126;
    }
    ptrace(PTRACE_CONT, root, NULL, NULL);

    int live = 1;
    int exec_count = 0;
    int root_result = 126;
    int root_done = 0;

    while (live > 0) {
        pid_t pid = waitpid(-1, &status, __WALL);
        if (pid < 0) {
            if (errno == EINTR) continue;
            break;
        }

        if (WIFEXITED(status)) {
            live--;
            if (pid == root) {
                root_result = WEXITSTATUS(status);
                root_done = 1;
            }
            continue;
        }
        if (WIFSIGNALED(status)) {
            live--;
            if (pid == root) {
                root_result = 128 + WTERMSIG(status);
                root_done = 1;
            }
            continue;
        }
        if (!WIFSTOPPED(status)) continue;

        unsigned int event = ((unsigned int)status) >> 16;
        if (event == PTRACE_EVENT_EXEC) {
            exec_count++;
            if (exec_count > 1) {
                kill(-root, SIGKILL);
                ptrace(PTRACE_KILL, pid, NULL, NULL);
                return 125;
            }
        } else if (event == PTRACE_EVENT_FORK ||
                   event == PTRACE_EVENT_VFORK ||
                   event == PTRACE_EVENT_CLONE) {
            live++;
        }

        int sig = WSTOPSIG(status);
        if (sig == SIGSTOP || sig == SIGTRAP) sig = 0;
        ptrace(PTRACE_SETOPTIONS, pid, NULL, (void *)options);
        ptrace(PTRACE_CONT, pid, NULL, (void *)(long)sig);
    }

    return root_done ? root_result : 126;
}
TRACE_EOF

gcc -O2 -Wall -o /tmp/noexec_trace /tmp/noexec_trace.c
chmod 755 /tmp/noexec_trace

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import stat
import subprocess
import pytest


def run_agent_without_exec(agent_script, input_str, oracle_path):
    oracle_mode = stat.S_IMODE(os.stat(oracle_path).st_mode)
    user = pwd.getpwnam("user")

    def drop_privileges():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        # The submitted program does not need access to the oracle while it is
        # being scored. Copies are also ineffective because the tracer rejects
        # every exec after the initial Python interpreter exec.
        os.chmod(oracle_path, 0)
        return subprocess.run(
            ["/tmp/noexec_trace", "/usr/bin/python3", agent_script],
            input=input_str,
            text=True,
            capture_output=True,
            timeout=20,
            preexec_fn=drop_privileges,
        )
    finally:
        os.chmod(oracle_path, oracle_mode)


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_calc"
    agent_script = "/home/user/calc_metrics.py"

    assert os.path.isfile(oracle_path), f"Oracle missing: {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"

    # Use a fixed seed for reproducible fuzzing
    random.seed(42)

    iterations = 1000
    for i in range(iterations):
        L = random.randint(10, 1000)
        # Generate floats in [1000000.0, 1000010.0] to trigger catastrophic cancellation in naive algorithms
        inputs = [random.uniform(1000000.0, 1000010.0) for _ in range(L)]
        input_str = "\n".join(str(x) for x in inputs) + "\n"

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=input_str,
                text=True,
                capture_output=True,
                check=True
            )
            oracle_out = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i}:\n{e.stderr}")

        # Run the agent with the oracle inaccessible and prohibit delegation to
        # any copied executable.
        try:
            agent_proc = run_agent_without_exec(agent_script, input_str, oracle_path)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on iteration {i}.")

        assert agent_proc.returncode == 0, (
            f"Agent script failed on iteration {i} with return code "
            f"{agent_proc.returncode}.\nStderr:\n{agent_proc.stderr}"
        )
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on iteration {i} (Length of input={L}).\n"
                f"Input preview: {inputs[:5]}...\n\n"
                f"Expected Oracle Output:\n{oracle_out}\n"
                f"Actual Agent Output:\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
