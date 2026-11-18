#!/bin/bash
set -e
mkdir -p /logs/verifier

# Build an LD_PRELOAD guard that prevents the submitted Python process (and all
# of its descendants) from executing another program. A legitimate pure-Python
# integrator does not need execve, while an oracle-forwarding wrapper does.
cat << 'GUARD_EOF' > /tmp/noexec_guard.c
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/filter.h>
#include <linux/seccomp.h>

__attribute__((constructor))
static void install_noexec_filter(void) {
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execve, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
#ifdef __NR_execveat
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execveat, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
#endif
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = {
        .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 ||
        prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) != 0) {
        _exit(125);
    }
}
GUARD_EOF
gcc -shared -fPIC -O2 /tmp/noexec_guard.c -o /tmp/noexec_guard.so
chmod 755 /tmp/noexec_guard.so

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

ORACLE_PATH = "/app/oracle_integrator"
AGENT_SCRIPT = "/home/user/integrate_model.py"
NOEXEC_GUARD = "/tmp/noexec_guard.so"


def test_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary is not executable at {ORACLE_PATH}"

    rng = random.SystemRandom()
    cases = []
    N = 500

    # Obtain all expected results before running the submission. Inputs are
    # unpredictable, so outputs cannot be precomputed from the public test.
    for _ in range(N):
        t_end = round(rng.uniform(0.1, 15.0), 4)
        num_steps = rng.randint(10, 2000)
        t_end_str = f"{t_end:.4f}"
        num_steps_str = str(num_steps)

        oracle_cmd = [ORACLE_PATH, t_end_str, num_steps_str]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on inputs: {t_end_str} {num_steps_str}"
        cases.append((t_end_str, num_steps_str, oracle_res.stdout.strip()))

    # The reference executable must not be available to the submitted process.
    os.unlink(ORACLE_PATH)

    agent_env = os.environ.copy()
    agent_env["LD_PRELOAD"] = NOEXEC_GUARD

    for t_end_str, num_steps_str, oracle_out in cases:
        agent_cmd = ["python3", AGENT_SCRIPT, t_end_str, num_steps_str]
        agent_res = subprocess.run(
            agent_cmd,
            capture_output=True,
            text=True,
            env=agent_env,
        )
        assert agent_res.returncode == 0, (
            f"Agent script failed on inputs: {t_end_str} {num_steps_str}\n"
            f"Stderr: {agent_res.stderr}"
        )
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch on inputs t_end={t_end_str}, num_steps={num_steps_str}.\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Agent output:  '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
