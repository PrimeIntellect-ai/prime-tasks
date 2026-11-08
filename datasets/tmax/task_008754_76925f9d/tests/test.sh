#!/bin/bash
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/deny_exec.c
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

static void mark_attempt(void) {
    int fd = open("/tmp/cred_server_exec_attempt", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        (void)write(fd, "exec\n", 5);
        close(fd);
    }
}

int execve(const char *path, char *const argv[], char *const envp[]) {
    mark_attempt(); errno = EPERM; return -1;
}
int execveat(int dirfd, const char *path, char *const argv[], char *const envp[], int flags) {
    mark_attempt(); errno = EPERM; return -1;
}
int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *actions,
                const posix_spawnattr_t *attr,
                char *const argv[], char *const envp[]) {
    mark_attempt(); errno = EPERM; return EPERM;
}
int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *actions,
                 const posix_spawnattr_t *attr,
                 char *const argv[], char *const envp[]) {
    mark_attempt(); errno = EPERM; return EPERM;
}
int system(const char *command) {
    mark_attempt(); errno = EPERM; return -1;
}
FILE *popen(const char *command, const char *type) {
    mark_attempt(); errno = EPERM; return NULL;
}
HOOK_EOF

gcc -shared -fPIC -o /tmp/deny_exec.so /tmp/deny_exec.c >/tmp/deny_exec_build.log 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import base64
import secrets
import subprocess
import pytest


def test_rotation_log_contents():
    log_path = '/home/user/rotation.log'
    assert os.path.isfile(log_path), f"The file {log_path} does not exist."

    with open(log_path, 'r') as f:
        content = f.read()

    expected = "admin:super_secret_password_123\ndb_user:db_pass_4567\n"
    # Allow missing trailing newline
    assert content.strip() == expected.strip(), "The contents of rotation.log do not match the expected plaintext credentials."


def test_cred_server_fixed_rs():
    fixed_path = '/home/user/cred_server_fixed.rs'
    assert os.path.isfile(fixed_path), f"The file {fixed_path} does not exist."

    with open(fixed_path, 'r') as f:
        content = f.read()

    # Preserve the original source assertions.
    assert 'Command::new("sh")' not in content, "The fixed Rust code still contains 'Command::new(\"sh\")'."
    assert 'Command::new("bash")' not in content, "The fixed Rust code still contains 'Command::new(\"bash\")'."
    assert 'fs::read_to_string' in content or 'File::open' in content, "The fixed Rust code must use 'fs::read_to_string' or 'File::open' for safe file reading."

    binary = '/tmp/cred_server_fixed_test'
    build = subprocess.run(
        ['rustc', fixed_path, '-o', binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"cred_server_fixed.rs does not compile:\n{build.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "rustc did not produce an executable server."

    # Aliasing or spelling Command differently must not hide use of std::process::Command.
    symbols = subprocess.run(
        ['nm', '-C', binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert symbols.returncode == 0, f"Could not inspect the compiled server: {symbols.stderr}"
    assert 'std::process::Command' not in symbols.stdout, "The compiled server still uses std::process::Command."

    preload = '/tmp/deny_exec.so'
    assert os.path.isfile(preload), "Failed to build the process-execution test helper."

    creds_path = '/home/user/data/creds_v2.enc'
    old_data = None
    old_mode = None
    if os.path.exists(creds_path):
        with open(creds_path, 'rb') as f:
            old_data = f.read()
        old_mode = stat.S_IMODE(os.stat(creds_path).st_mode)

    token = secrets.token_hex(16)
    wanted_line = f"acct_{token}:value_{secrets.token_hex(12)}"
    unrelated_line = f"other_{secrets.token_hex(16)}:do_not_return"
    injection = f"inj_{secrets.token_hex(12)}; touch /tmp/cred_server_injected; #"
    injection_line = f"account:{injection}:safe_value_{secrets.token_hex(8)}"
    test_data = f"{unrelated_line}\n{wanted_line}\n{injection_line}\n"

    exec_marker = '/tmp/cred_server_exec_attempt'
    injected_marker = '/tmp/cred_server_injected'
    for marker in (exec_marker, injected_marker):
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['LD_PRELOAD'] = preload

    try:
        with open(creds_path, 'w') as f:
            f.write(test_data)
        os.chmod(creds_path, 0o400)

        normal = subprocess.run(
            [binary, token],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=10,
        )
        assert normal.returncode == 0, f"The fixed server failed on a normal lookup: {normal.stderr}"
        assert wanted_line in normal.stdout, "The fixed server did not return the dynamically generated matching credential line."
        assert unrelated_line not in normal.stdout, "The fixed server returned an unrelated credential line."
        assert injection_line not in normal.stdout, "The fixed server returned a non-matching credential line."

        attacked = subprocess.run(
            [binary, injection],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=10,
        )
        assert attacked.returncode == 0, f"The fixed server failed when metacharacters were supplied as data: {attacked.stderr}"
        assert injection_line in attacked.stdout, "The fixed server did not treat shell metacharacters as literal lookup text."
        assert unrelated_line not in attacked.stdout, "The fixed server returned an unrelated line for the metacharacter lookup."
        assert not os.path.exists(injected_marker), "Supplying a username caused a shell command to execute."
        assert not os.path.exists(exec_marker), "The fixed server attempted to execute an external process."
    finally:
        if old_data is None:
            try:
                os.unlink(creds_path)
            except FileNotFoundError:
                pass
        else:
            with open(creds_path, 'wb') as f:
                f.write(old_data)
            os.chmod(creds_path, old_mode)
        for marker in (exec_marker, injected_marker):
            try:
                os.unlink(marker)
            except FileNotFoundError:
                pass


def test_creds_v2_enc_exists_and_permissions():
    creds_v2_path = '/home/user/data/creds_v2.enc'
    assert os.path.isfile(creds_v2_path), f"The file {creds_v2_path} does not exist."

    st = os.stat(creds_v2_path)
    # Check if permissions are exactly 0400
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o400, f"The permissions of {creds_v2_path} are {oct(perms)}, expected 0o400."


def test_creds_v2_enc_content():
    creds_v2_path = '/home/user/data/creds_v2.enc'
    assert os.path.isfile(creds_v2_path), f"The file {creds_v2_path} does not exist."

    with open(creds_v2_path, 'rb') as f:
        encoded_data = f.read()

    try:
        encrypted_bytes = base64.b64decode(encoded_data)
    except Exception as e:
        pytest.fail(f"Failed to base64 decode {creds_v2_path}: {e}")

    key = "NEW_KEY_99887766"
    decrypted = bytearray()
    for i in range(len(encrypted_bytes)):
        decrypted.append(encrypted_bytes[i] ^ ord(key[i % len(key)]))

    expected_pt = b"admin:super_secret_password_123\ndb_user:db_pass_4567\n"
    # Allow missing trailing newline if the student wrote it without one
    assert decrypted.strip() == expected_pt.strip(), "The decrypted contents of creds_v2.enc do not match the expected plaintext."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
