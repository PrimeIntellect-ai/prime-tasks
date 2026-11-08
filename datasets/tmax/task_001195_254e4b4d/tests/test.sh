#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SECCOMP_EOF' > /tmp/noexec.c
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <sys/prctl.h>
#include <sys/syscall.h>

__attribute__((constructor)) static void install_filter(void) {
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_execve, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
#ifdef SYS_execveat
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, SYS_execveat, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | (EPERM & SECCOMP_RET_DATA)),
#endif
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = {
        .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0)
        _exit(125);
    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) != 0)
        _exit(126);
}
SECCOMP_EOF

gcc -shared -fPIC -O2 /tmp/noexec.c -o /tmp/libnoexec.so
chmod 755 /tmp/libnoexec.so

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import os
import pwd
import random
import shutil
import string
import subprocess
import tempfile

ORACLE_PATH = "/app/oracle_validator"
AGENT_SCRIPT = "/home/user/payload_generator.py"
NOEXEC_LIBRARY = "/tmp/libnoexec.so"
NUM_TESTS = 10000


def expected_payload(value):
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()
    encoded = base64.b64encode(f"{value}:{digest}".encode("utf-8")).decode("ascii")
    return f"KNOCK-PAYLOAD-{encoded[::-1]}\n"


def demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_payload_generator_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle {ORACLE_PATH} is not executable"
    assert os.path.isfile(NOEXEC_LIBRARY)

    # Hide the supplied executable while submissions run. The seccomp filter also
    # prevents a submission from executing a copy it made during the agent phase.
    stash_dir = tempfile.mkdtemp(prefix="verifier-oracle-")
    os.chmod(stash_dir, 0o700)
    stashed_oracle = os.path.join(stash_dir, "oracle_validator")
    os.rename(ORACLE_PATH, stashed_oracle)

    try:
        charset = string.ascii_letters + string.digits + "!@#$%^&*"
        random.seed(42)
        inputs = [
            "".join(random.choices(charset, k=random.randint(8, 128)))
            for _ in range(NUM_TESTS)
        ]

        environment = os.environ.copy()
        environment["LD_PRELOAD"] = NOEXEC_LIBRARY
        environment["HOME"] = "/home/user"

        for i, test_input in enumerate(inputs):
            agent_proc = subprocess.run(
                ["python3", AGENT_SCRIPT, test_input],
                capture_output=True,
                text=True,
                env=environment,
                preexec_fn=demote_to_user,
            )
            expected = expected_payload(test_input)

            assert agent_proc.returncode == 0, (
                f"Agent script failed on input: {test_input}\n"
                f"Error: {agent_proc.stderr}"
            )
            assert agent_proc.stdout.strip() == expected.strip(), (
                f"Mismatch on test {i+1}/{NUM_TESTS}\n"
                f"Input: {test_input}\n"
                f"Expected Output: {expected.strip()}\n"
                f"Agent Output   : {agent_proc.stdout.strip()}"
            )
            assert agent_proc.stdout == expected, (
                f"Output was not perfectly formatted on test {i+1}/{NUM_TESTS}"
            )
    finally:
        if os.path.exists(stashed_oracle):
            os.rename(stashed_oracle, ORACLE_PATH)
        shutil.rmtree(stash_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
