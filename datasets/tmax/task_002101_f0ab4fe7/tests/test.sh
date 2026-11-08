#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import random
import stat
import subprocess

import pytest

ORACLE = "/app/oracle_processor"
AGENT = "/home/user/workspace/processor_fixed"
WORKSPACE = "/home/user/workspace"
BLOCKER = "/tmp/verifier_no_delegate.so"
HIDDEN_ORACLE = "/root/.verifier_hidden_oracle_processor"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def drop_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def run_agent(input_data, timeout=10):
    env = os.environ.copy()
    env["LD_PRELOAD"] = BLOCKER

    # Make the named oracle unavailable while the submission runs. The preload
    # library also prevents wrappers from delegating to copied executables.
    os.replace(ORACLE, HIDDEN_ORACLE)
    try:
        return subprocess.run(
            [AGENT],
            input=input_data,
            capture_output=True,
            timeout=timeout,
            env=env,
            preexec_fn=drop_to_user,
        )
    finally:
        os.replace(HIDDEN_ORACLE, ORACLE)


@pytest.fixture(scope="session", autouse=True)
def prepare_and_validate_build():
    blocker_source = r'''
#define _GNU_SOURCE
#include <errno.h>
#include <spawn.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

static int denied(void) { errno = EPERM; return -1; }
int execve(const char *p, char *const a[], char *const e[]) { return denied(); }
int execv(const char *p, char *const a[]) { return denied(); }
int execvp(const char *p, char *const a[]) { return denied(); }
int execvpe(const char *p, char *const a[], char *const e[]) { return denied(); }
int execveat(int d, const char *p, char *const a[], char *const e[], int f) { return denied(); }
int execl(const char *p, const char *a, ...) { return denied(); }
int execlp(const char *p, const char *a, ...) { return denied(); }
int execle(const char *p, const char *a, ...) { return denied(); }
int system(const char *s) { return denied(); }
FILE *popen(const char *s, const char *m) { errno = EPERM; return NULL; }
pid_t fork(void) { errno = EPERM; return -1; }
pid_t vfork(void) { errno = EPERM; return -1; }
int posix_spawn(pid_t *p, const char *path, const posix_spawn_file_actions_t *fa,
                const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return EPERM;
}
int posix_spawnp(pid_t *p, const char *path, const posix_spawn_file_actions_t *fa,
                 const posix_spawnattr_t *attr, char *const argv[], char *const envp[]) {
    return EPERM;
}
'''
    with open("/tmp/verifier_no_delegate.c", "w") as f:
        f.write(blocker_source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "/tmp/verifier_no_delegate.c", "-o", BLOCKER],
        check=True,
        capture_output=True,
        timeout=30,
    )

    assert os.path.exists(ORACLE), f"Oracle binary not found at {ORACLE}"
    assert os.access(ORACLE, os.X_OK), f"Oracle binary at {ORACLE} is not executable"

    # Retain the original final-artifact assertions before rebuilding.
    assert os.path.exists(AGENT), f"Agent binary not found at {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Agent binary at {AGENT} is not executable"

    # The submitted Makefile and source must actually produce the requested artifact.
    os.unlink(AGENT)
    build = subprocess.run(
        ["make", "-B"], cwd=WORKSPACE, capture_output=True, timeout=60
    )
    assert build.returncode == 0, (
        "Submitted project does not build successfully:\n"
        + build.stdout.decode("utf-8", "replace")
        + build.stderr.decode("utf-8", "replace")
    )

    assert os.path.exists(AGENT), f"Build did not create {AGENT}"
    info = os.lstat(AGENT)
    assert stat.S_ISREG(info.st_mode), "processor_fixed must be a regular file, not a symlink or wrapper script"
    assert not (info.st_mode & (stat.S_ISUID | stat.S_ISGID)), "processor_fixed must not be setuid/setgid"
    assert os.access(AGENT, os.X_OK), f"Agent binary at {AGENT} is not executable"
    with open(AGENT, "rb") as f:
        assert f.read(4) == b"\x7fELF", "processor_fixed must be a compiled ELF executable"
    assert sha256(AGENT) != sha256(ORACLE), "processor_fixed must not be a copy of the legacy binary"


def test_fuzz_equivalence():
    random.seed(42)
    num_iterations = 100

    for i in range(num_iterations):
        num_ints = random.randint(1_000, 100_000)
        ints = [str(random.randint(-10_000, 10_000)) for _ in range(num_ints)]
        input_data = " ".join(ints).encode("utf-8")

        oracle_proc = subprocess.run(
            [ORACLE], input=input_data, capture_output=True, timeout=10
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"
        oracle_output = oracle_proc.stdout.decode("utf-8").strip()

        agent_proc = run_agent(input_data)
        assert agent_proc.returncode == 0, (
            f"Agent binary failed on iteration {i} with stderr: "
            f"{agent_proc.stderr.decode('utf-8', 'replace')}"
        )
        agent_output = agent_proc.stdout.decode("utf-8").strip()
        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i}.\n"
            f"Input size: {num_ints} integers\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )


def test_independent_expected_results_and_contention():
    cases = [
        [],
        [-5, -2, -1, 0, 1, 2, 3, 4, 9, 10],
        [10000, -10000, 9998, -9998] * 25000,
    ]
    rng = random.Random(918273)
    cases.append([rng.randint(-10000, 10000) for _ in range(150000)])

    for case_index, values in enumerate(cases):
        expected = str(sum(v * v for v in values if v >= 0 and v % 2 == 0))
        input_data = "\n".join(map(str, values)).encode("utf-8")
        repetitions = 12 if len(values) >= 100000 else 1
        for repetition in range(repetitions):
            proc = run_agent(input_data, timeout=10)
            assert proc.returncode == 0, (
                f"Agent failed for independent case {case_index}, repetition {repetition}: "
                f"{proc.stderr.decode('utf-8', 'replace')}"
            )
            assert proc.stdout.decode("utf-8").strip() == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    if [ -e /root/.verifier_hidden_oracle_processor ] && [ ! -e /app/oracle_processor ]; then
        mv /root/.verifier_hidden_oracle_processor /app/oracle_processor
    fi
    echo "0" > /logs/verifier/reward.txt
fi
