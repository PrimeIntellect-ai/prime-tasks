#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/auth_unset_hook.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>

static int is_auth_token(const char *s) {
    static const char expected[] = "AUTH_TOKEN";
    int i = 0;
    if (!s) return 0;
    while (expected[i] && s[i] == expected[i]) i++;
    return expected[i] == '\0' && s[i] == '\0';
}

int unsetenv(const char *name) {
    static int (*real_unsetenv)(const char *) = 0;
    if (!real_unsetenv)
        real_unsetenv = (int (*)(const char *))dlsym(RTLD_NEXT, "unsetenv");

    int rc = real_unsetenv ? real_unsetenv(name) : -1;
    if (is_auth_token(name)) {
        int fd = open("/tmp/verifier_auth_unset.trace",
                      O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) {
            (void)write(fd, "AUTH_TOKEN_UNSET\n", 17);
            close(fd);
        }
    }
    return rc;
}
HOOK_EOF

gcc -shared -fPIC /tmp/auth_unset_hook.c -o /tmp/auth_unset_hook.so -ldl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import subprocess

C_FILE = "/home/user/auth_server.c"
BIN_FILE = "/home/user/auth_server"
FRESH_BIN = "/tmp/auth_server_from_source"
RESULT_FILE = "/home/user/auth_result.txt"
HOOK_FILE = "/tmp/auth_unset_hook.so"
TRACE_FILE = "/tmp/verifier_auth_unset.trace"
EXPECTED_TOKEN = b"SuperSecretAppToken2024"
ENCODED_TOKEN = base64.b64encode(EXPECTED_TOKEN).decode("ascii")


def test_source_code_constraints():
    assert os.path.isfile(C_FILE), f"Source file {C_FILE} is missing."
    with open(C_FILE, "r") as f:
        content = f.read()

    assert 'unsetenv("AUTH_TOKEN")' in content.replace(" ", ""), \
        'The source code does not contain unsetenv("AUTH_TOKEN").'
    assert "argv[1]" not in content, \
        "The source code still contains references to argv[1], which should be removed."


def test_executable_exists():
    assert os.path.isfile(BIN_FILE), f"Executable {BIN_FILE} is missing. Did you compile it?"
    assert os.access(BIN_FILE, os.X_OK), f"File {BIN_FILE} is not executable."


def test_source_compiles_independently():
    proc = subprocess.run(
        ["gcc", C_FILE, "-o", FRESH_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")
    assert os.path.isfile(FRESH_BIN) and os.access(FRESH_BIN, os.X_OK)


def test_no_encoded_token_shortcut_in_executables():
    # A compliant implementation hardcodes only the decoded expected value. The
    # Base64 input itself must be decoded rather than embedded as an answer key.
    needle = ENCODED_TOKEN.encode("ascii")
    for executable in (BIN_FILE, FRESH_BIN):
        with open(executable, "rb") as f:
            data = f.read()
        assert needle not in data, \
            f"{executable} embeds the known Base64 input instead of decoding it"


def run_auth_server(executable, auth_value=None, args=()):
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)
    if os.path.exists(TRACE_FILE):
        os.remove(TRACE_FILE)

    env = os.environ.copy()
    env.pop("AUTH_TOKEN", None)
    old_preload = env.get("LD_PRELOAD", "")
    env["LD_PRELOAD"] = HOOK_FILE + ((":" + old_preload) if old_preload else "")
    if auth_value is not None:
        env["AUTH_TOKEN"] = auth_value

    proc = subprocess.run(
        [executable, *args],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )

    result = None
    if os.path.exists(RESULT_FILE):
        with open(RESULT_FILE, "r") as f:
            result = f.read().strip()

    trace = ""
    if os.path.exists(TRACE_FILE):
        with open(TRACE_FILE, "r") as f:
            trace = f.read()

    combined_output = proc.stdout + proc.stderr
    assert EXPECTED_TOKEN not in combined_output, "The decoded token was printed"
    assert ENCODED_TOKEN.encode() not in combined_output, "The encoded token was printed"
    if auth_value is not None:
        assert "AUTH_TOKEN_UNSET\n" in trace, \
            "The executable did not actually call unsetenv(\"AUTH_TOKEN\")"
    return result


def binaries():
    return (BIN_FILE, FRESH_BIN)


def test_valid_token():
    for executable in binaries():
        result = run_auth_server(executable, ENCODED_TOKEN)
        assert result == "AUTH_SUCCESS", \
            f"Expected AUTH_SUCCESS for valid token from {executable}, got {result}"


def test_invalid_token():
    invalid_plaintexts = [b"BadToken", b"SuperSecretAppToken2023", b"SuperSecretAppToken2024!"]
    invalid_plaintexts.extend(secrets.token_bytes(n) for n in (1, 2, 7, 16, 31, 48))
    invalid_encodings = [base64.b64encode(v).decode("ascii") for v in invalid_plaintexts]
    invalid_encodings.extend(["!not-base64!", "====", "A", "U3VwZXI="])

    for executable in binaries():
        for encoded in invalid_encodings:
            result = run_auth_server(executable, encoded)
            assert result == "AUTH_FAILURE", \
                f"Expected AUTH_FAILURE for invalid input {encoded!r}, got {result}"


def test_missing_token():
    for executable in binaries():
        result = run_auth_server(executable)
        assert result == "AUTH_FAILURE", \
            f"Expected AUTH_FAILURE for missing token, got {result}"


def test_command_line_arguments_are_not_credentials():
    for executable in binaries():
        result = run_auth_server(executable, None, (EXPECTED_TOKEN.decode(),))
        assert result == "AUTH_FAILURE", "A command-line token was accepted"

        result = run_auth_server(executable, base64.b64encode(b"wrong").decode(),
                                 (EXPECTED_TOKEN.decode(),))
        assert result == "AUTH_FAILURE", "argv overrode an invalid environment token"

        result = run_auth_server(executable, ENCODED_TOKEN, ("irrelevant-argument",))
        assert result == "AUTH_SUCCESS", "An extra argument changed valid environment authentication"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
