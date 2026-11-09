#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

# Remove any agent-owned helper process started before verification.
pkill -KILL -u user 2>/dev/null || true

cat << 'RUNNER_EOF' > /tmp/noexec_runner.c
#define _GNU_SOURCE
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <signal.h>
#include <pwd.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define MAXP 4096

struct proc_state {
    pid_t pid;
    int seen_exec;
};

static struct proc_state procs[MAXP];
static int nprocs = 0;

static int find_proc(pid_t pid) {
    for (int i = 0; i < nprocs; i++)
        if (procs[i].pid == pid) return i;
    return -1;
}

static void add_proc(pid_t pid, int seen_exec) {
    int i = find_proc(pid);
    if (i >= 0) {
        procs[i].seen_exec = seen_exec;
        return;
    }
    if (nprocs >= MAXP) _exit(125);
    procs[nprocs].pid = pid;
    procs[nprocs].seen_exec = seen_exec;
    nprocs++;
}

static void remove_proc(pid_t pid) {
    int i = find_proc(pid);
    if (i < 0) return;
    procs[i] = procs[nprocs - 1];
    nprocs--;
}

static void kill_all(void) {
    for (int i = 0; i < nprocs; i++) kill(procs[i].pid, SIGKILL);
}

int main(int argc, char **argv) {
    if (argc < 3) return 125;

    struct passwd *pw = getpwnam(argv[1]);
    if (!pw) return 125;

    pid_t child = fork();
    if (child < 0) return 125;

    if (child == 0) {
        if (ptrace(PTRACE_TRACEME, 0, 0, 0) < 0) _exit(125);
        raise(SIGSTOP);
        if (setgroups(0, NULL) < 0) _exit(125);
        if (setgid(pw->pw_gid) < 0) _exit(125);
        if (setuid(pw->pw_uid) < 0) _exit(125);
        execvp(argv[2], &argv[2]);
        _exit(127);
    }

    int status;
    if (waitpid(child, &status, 0) < 0 || !WIFSTOPPED(status)) {
        kill(child, SIGKILL);
        return 125;
    }

    long opts = PTRACE_O_TRACEEXEC | PTRACE_O_TRACEFORK |
                PTRACE_O_TRACEVFORK | PTRACE_O_TRACECLONE |
                PTRACE_O_EXITKILL;
    if (ptrace(PTRACE_SETOPTIONS, child, 0, opts) < 0) {
        kill(child, SIGKILL);
        return 125;
    }

    add_proc(child, 0);
    ptrace(PTRACE_CONT, child, 0, 0);
    int root_status = 125;
    int forbidden = 0;

    while (nprocs > 0) {
        pid_t pid = waitpid(-1, &status, __WALL);
        if (pid < 0) break;
        int idx = find_proc(pid);
        if (idx < 0) {
            add_proc(pid, 1);
            idx = find_proc(pid);
            ptrace(PTRACE_SETOPTIONS, pid, 0, opts);
        }

        if (WIFEXITED(status) || WIFSIGNALED(status)) {
            if (pid == child) {
                root_status = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
            }
            remove_proc(pid);
            continue;
        }

        if (!WIFSTOPPED(status)) continue;

        unsigned int event = (unsigned int)status >> 16;
        int sig = WSTOPSIG(status);

        if (event == PTRACE_EVENT_EXEC) {
            if (procs[idx].seen_exec) {
                forbidden = 1;
                kill_all();
                continue;
            }
            procs[idx].seen_exec = 1;
            ptrace(PTRACE_CONT, pid, 0, 0);
            continue;
        }

        if (event == PTRACE_EVENT_FORK || event == PTRACE_EVENT_VFORK ||
            event == PTRACE_EVENT_CLONE) {
            unsigned long newpid = 0;
            ptrace(PTRACE_GETEVENTMSG, pid, 0, &newpid);
            if (newpid) add_proc((pid_t)newpid, procs[idx].seen_exec);
            ptrace(PTRACE_CONT, pid, 0, 0);
            continue;
        }

        if (sig == SIGSTOP || sig == SIGTRAP) sig = 0;
        ptrace(PTRACE_CONT, pid, 0, sig);
    }

    if (forbidden) return 126;
    return root_status;
}
RUNNER_EOF

gcc -O2 -Wall -o /tmp/noexec_runner /tmp/noexec_runner.c
chmod 755 /tmp/noexec_runner

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile
import h5py

ORACLE_PATH = "/app/profiler_sim"
AGENT_PATH = "/home/user/solution.py"
RUNNER_PATH = "/tmp/noexec_runner"
NUM_ITERATIONS = 100


def test_solution_exists():
    assert os.path.exists(AGENT_PATH), f"Agent solution not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent solution {AGENT_PATH} is not a file"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable"

    random.seed(42)
    cases = []
    private_dir = None
    hidden_oracle = None

    try:
        # Derive all expected answers before making the supplied binary unavailable
        # to the submitted program.
        for i in range(NUM_ITERATIONS):
            x0 = random.uniform(0.1, 2.0)
            v0 = random.uniform(0.1, 2.0)
            dt_base = random.uniform(0.1, 2.0)

            fd, tmp_path = tempfile.mkstemp(suffix=".h5")
            os.close(fd)
            with h5py.File(tmp_path, "w") as f:
                f.create_dataset("/initial_state", data=[x0, v0, dt_base], dtype="float64")
            os.chmod(tmp_path, 0o644)

            oracle_res = subprocess.run(
                [ORACLE_PATH, tmp_path], capture_output=True, text=True, timeout=10
            )
            assert oracle_res.returncode == 0, (
                f"Oracle failed on iteration {i} with input {[x0, v0, dt_base]}"
            )
            cases.append((i, x0, v0, dt_base, tmp_path, oracle_res.stdout.strip()))

        private_dir = tempfile.mkdtemp(prefix=".verifier-oracle-", dir="/app")
        os.chmod(private_dir, 0o700)
        hidden_oracle = os.path.join(private_dir, "profiler_sim")
        os.rename(ORACLE_PATH, hidden_oracle)

        for i, x0, v0, dt_base, tmp_path, oracle_out in cases:
            agent_res = subprocess.run(
                [RUNNER_PATH, "user", "python3", AGENT_PATH, tmp_path],
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert agent_res.returncode == 0, (
                f"Agent script failed on iteration {i} with input {[x0, v0, dt_base]}\n"
                f"Stderr: {agent_res.stderr}"
            )
            agent_out = agent_res.stdout.strip()
            assert oracle_out == agent_out, (
                f"Mismatch on iteration {i} with input "
                f"[x0={x0}, v0={v0}, dt_base={dt_base}].\n"
                f"Oracle output: {oracle_out}\nAgent output: {agent_out}"
            )
    finally:
        for case in cases:
            tmp_path = case[4]
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
        if hidden_oracle and os.path.exists(hidden_oracle):
            os.rename(hidden_oracle, ORACLE_PATH)
        if private_dir and os.path.isdir(private_dir):
            shutil.rmtree(private_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
