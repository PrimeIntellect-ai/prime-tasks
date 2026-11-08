#!/bin/bash
set +e
mkdir -p /logs/verifier

tmpdir=$(mktemp -d /tmp/log-auditor-verifier.XXXXXX)
if [ -z "$tmpdir" ] || [ ! -d "$tmpdir" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# Terminate any oracle proxy the unprivileged agent may have left running.
pkill -KILL -u user >/dev/null 2>&1 || true

cat > "$tmpdir/no_delegate.c" <<'C_EOF'
#define _GNU_SOURCE
#include <errno.h>
#include <stddef.h>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <linux/filter.h>
#include <linux/seccomp.h>

__attribute__((constructor)) static void install_filter(void) {
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
#ifdef __NR_execve
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execve, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
#ifdef __NR_execveat
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execveat, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
#ifdef __NR_socket
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_socket, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
#ifdef __NR_socketpair
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_socketpair, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
#ifdef __NR_connect
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_connect, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
#ifdef __NR_bind
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_bind, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
#ifdef __NR_listen
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_listen, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
#ifdef __NR_accept
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_accept, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
#ifdef __NR_accept4
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_accept4, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
#endif
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = {
        .len = (unsigned short)(sizeof(filter) / sizeof(filter[0])),
        .filter = filter,
    };

    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0 ||
        prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program) != 0) {
        _exit(126);
    }
}
C_EOF

cat > "$tmpdir/test_final_state.py" <<'PY_EOF'
import os
import pwd
import random
import string
import subprocess

ORACLE_PATH = "/app/log_auditor"
AGENT_SCRIPT = "/home/user/emulator.py"
BLOCKER_PATH = os.environ["BLOCKER_PATH"]


def generate_test_cases(n=1000):
    rng = random.SystemRandom()
    cases = []
    chars = string.ascii_letters + string.digits + string.punctuation

    for _ in range(n):
        csp_length = rng.randint(10, 50)
        csp = ''.join(rng.choice(chars) for _ in range(csp_length))
        if rng.random() < 0.3:
            csp += " script-src 'self'"

        payload_length = rng.randint(5, 100)
        payload_bytes = bytearray(rng.getrandbits(8) for _ in range(payload_length))

        if rng.random() < 0.3 and payload_length >= 11:
            ssn = f"{rng.randint(100,999):03d}-{rng.randint(10,99):02d}-{rng.randint(1000,9999):04d}"
            ssn_bytes = ssn.encode("ascii")
            insert_idx = rng.randint(0, payload_length - len(ssn_bytes))
            payload_bytes[insert_idx:insert_idx + len(ssn_bytes)] = ssn_bytes

        state = 0x5A
        ciphertext = bytearray()
        for byte in payload_bytes:
            state = (state * 31 + 17) & 0xFF
            ciphertext.append(byte ^ state)

        cases.append(f"CSP: {csp} | PAYLOAD: {ciphertext.hex()}\n")

    return cases


def run_oracle(input_str):
    result = subprocess.run(
        [ORACLE_PATH], input=input_str, text=True,
        capture_output=True, timeout=2
    )
    return result.stdout


def demote_to_agent_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def run_agent(input_str):
    env = os.environ.copy()
    env["LD_PRELOAD"] = BLOCKER_PATH
    result = subprocess.run(
        ["python3", AGENT_SCRIPT], input=input_str, text=True,
        capture_output=True, timeout=2, env=env,
        preexec_fn=demote_to_agent_user
    )
    return result.stdout


def test_emulator_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert not os.path.islink(AGENT_SCRIPT), "Agent script must be a regular Python file"

    test_cases = generate_test_cases(1000)
    expected = []
    try:
        for input_str in test_cases:
            expected.append(run_oracle(input_str))
    finally:
        # The agent may inspect the binary while solving, but it must not be
        # available while the submitted implementation is being evaluated.
        try:
            os.unlink(ORACLE_PATH)
        except FileNotFoundError:
            pass

    assert not os.path.exists(ORACLE_PATH)

    for i, (input_str, oracle_out) in enumerate(zip(test_cases, expected), 1):
        agent_out = run_agent(input_str)
        assert oracle_out == agent_out, (
            f"Output mismatch on test case {i}:\n"
            f"Input:\n{input_str}\n"
            f"Oracle Output:\n{oracle_out}\n"
            f"Agent Output:\n{agent_out}\n"
        )
PY_EOF

reward=0
if gcc -shared -fPIC -O2 -o "$tmpdir/libno_delegate.so" "$tmpdir/no_delegate.c"; then
    chmod 755 "$tmpdir" "$tmpdir/libno_delegate.so"
    if BLOCKER_PATH="$tmpdir/libno_delegate.so" python3 -m pytest "$tmpdir/test_final_state.py" -x --tb=short 2>&1; then
        reward=1
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
rm -rf "$tmpdir"
exit 0
