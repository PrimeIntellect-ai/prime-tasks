#!/bin/bash
mkdir -p /logs/verifier

cat << 'BLOCK_EOF' > /tmp/verifier_noexec.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int allowed_interpreter(const char *path) {
    if (!path) return 0;

    char resolved[PATH_MAX];
    const char *checked = path;
    if (strchr(path, '/') && realpath(path, resolved)) checked = resolved;

    const char *base = strrchr(checked, '/');
    base = base ? base + 1 : checked;

    int trusted_dir = !strchr(checked, '/') ||
        strncmp(checked, "/usr/bin/", 9) == 0 ||
        strncmp(checked, "/bin/", 5) == 0 ||
        strncmp(checked, "/usr/local/bin/", 15) == 0;
    if (!trusted_dir) return 0;

    return strncmp(base, "python", 6) == 0 ||
           strcmp(base, "sh") == 0 || strcmp(base, "bash") == 0 ||
           strcmp(base, "dash") == 0 || strncmp(base, "perl", 4) == 0 ||
           strncmp(base, "ruby", 4) == 0 || strncmp(base, "node", 4) == 0 ||
           strncmp(base, "php", 3) == 0 || strncmp(base, "lua", 3) == 0;
}

int execve(const char *p, char *const a[], char *const e[]) {
    if (!allowed_interpreter(p)) { errno = EACCES; return -1; }
    static int (*real_fn)(const char *, char *const[], char *const[]);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "execve");
    return real_fn(p, a, e);
}

int execveat(int d, const char *p, char *const a[], char *const e[], int f) {
    if (!allowed_interpreter(p)) { errno = EACCES; return -1; }
    static int (*real_fn)(int, const char *, char *const[], char *const[], int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "execveat");
    return real_fn(d, p, a, e, f);
}

int execv(const char *p, char *const a[]) {
    extern char **environ;
    return execve(p, a, environ);
}

int execvp(const char *p, char *const a[]) {
    if (!allowed_interpreter(p)) { errno = EACCES; return -1; }
    static int (*real_fn)(const char *, char *const[]);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "execvp");
    return real_fn(p, a);
}

int execvpe(const char *p, char *const a[], char *const e[]) {
    if (!allowed_interpreter(p)) { errno = EACCES; return -1; }
    static int (*real_fn)(const char *, char *const[], char *const[]);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "execvpe");
    return real_fn(p, a, e);
}

int posix_spawn(pid_t *pid, const char *p,
                const posix_spawn_file_actions_t *fa,
                const posix_spawnattr_t *attr,
                char *const a[], char *const e[]) {
    if (!allowed_interpreter(p)) return EACCES;
    static int (*real_fn)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                          const posix_spawnattr_t *, char *const[], char *const[]);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "posix_spawn");
    return real_fn(pid, p, fa, attr, a, e);
}

int posix_spawnp(pid_t *pid, const char *p,
                 const posix_spawn_file_actions_t *fa,
                 const posix_spawnattr_t *attr,
                 char *const a[], char *const e[]) {
    if (!allowed_interpreter(p)) return EACCES;
    static int (*real_fn)(pid_t *, const char *, const posix_spawn_file_actions_t *,
                          const posix_spawnattr_t *, char *const[], char *const[]);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "posix_spawnp");
    return real_fn(pid, p, fa, attr, a, e);
}

int system(const char *command) { errno = EACCES; return -1; }
FILE *popen(const char *command, const char *type) { errno = EACCES; return NULL; }
BLOCK_EOF

gcc -shared -fPIC -O2 -o /tmp/verifier_noexec.so /tmp/verifier_noexec.c -ldl >/tmp/verifier_compile.log 2>&1
chmod 755 /tmp/verifier_noexec.so 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import stat
import subprocess
import uuid
import pytest

AGENT = "/home/user/new_token_gen"
ORACLE = "/app/oracle_token_gen"
LEGACY = "/app/legacy_token_gen"
BLOCKER = "/tmp/verifier_noexec.so"

def test_agent_executable_exists():
    assert os.path.exists(AGENT), f"Agent program not found at {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Agent program {AGENT} is not executable"
    assert stat.S_ISREG(os.stat(AGENT, follow_symlinks=True).st_mode), "Agent program must be a regular file"

def test_agent_is_an_independent_script():
    assert os.path.exists(ORACLE), f"Oracle program not found at {ORACLE}"
    assert os.path.exists(LEGACY), f"Legacy program not found at {LEGACY}"
    assert os.path.exists(BLOCKER), "Verifier execution guard was not built"

    with open(AGENT, "rb") as f:
        agent_data = f.read()
    with open(ORACLE, "rb") as f:
        oracle_data = f.read()
    with open(LEGACY, "rb") as f:
        legacy_data = f.read()

    assert agent_data != oracle_data, "Agent program is a copy of the oracle"
    assert agent_data != legacy_data, "Agent program is a copy of the legacy binary"
    assert not agent_data.startswith(b"\x7fELF"), "Replacement must be an independently implemented script, not a copied binary"
    assert b"\x00" not in agent_data, "Replacement must be a textual script"
    try:
        source = agent_data.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail("Replacement must be a UTF-8 textual script")
    assert source.startswith("#!"), "Replacement script must have an interpreter shebang"
    assert "/app/oracle_token_gen" not in source, "Replacement must not invoke the oracle"
    assert "/app/legacy_token_gen" not in source, "Replacement must not invoke the legacy binary"

def _demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE), f"Oracle program not found at {ORACLE}"

    random.seed(42)
    inputs = [str(random.randint(1000, 999999)) for _ in range(500)]
    expected = []

    for inp in inputs:
        try:
            oracle_res = subprocess.run([ORACLE, inp], capture_output=True, text=True, timeout=2)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {inp}")
        assert oracle_res.returncode == 0, f"Oracle failed on input {inp}"
        expected.append(oracle_res.stdout)

    token = uuid.uuid4().hex
    hidden_oracle = f"/app/.verifier-hidden-oracle-{token}"
    hidden_legacy = f"/app/.verifier-hidden-legacy-{token}"
    app_mode = stat.S_IMODE(os.stat("/app").st_mode)

    os.replace(ORACLE, hidden_oracle)
    os.replace(LEGACY, hidden_legacy)
    os.chmod("/app", 0o700)

    env = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": "/home/user",
        "LANG": "C.UTF-8",
        "LC_ALL": "C.UTF-8",
        "LD_PRELOAD": BLOCKER,
    }

    try:
        for inp, oracle_out in zip(inputs, expected):
            try:
                agent_res = subprocess.run(
                    [AGENT, inp],
                    capture_output=True,
                    text=True,
                    timeout=2,
                    env=env,
                    preexec_fn=_demote_to_user,
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"Agent program timed out on input {inp}")

            assert agent_res.returncode == 0, (
                f"Agent program failed on input {inp} with return code "
                f"{agent_res.returncode}: {agent_res.stderr!r}"
            )
            assert agent_res.stdout == oracle_out, (
                f"Output mismatch on input {inp}.\n"
                f"Oracle output: {oracle_out!r}\n"
                f"Agent output: {agent_res.stdout!r}"
            )
    finally:
        os.replace(hidden_oracle, ORACLE)
        os.replace(hidden_legacy, LEGACY)
        os.chmod("/app", app_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
