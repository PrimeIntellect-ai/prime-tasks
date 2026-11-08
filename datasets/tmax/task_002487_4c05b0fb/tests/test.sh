#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import subprocess

WRAPPER = "/home/user/secure_wrapper"
SOURCE = "/home/user/secure_wrapper.c"
PARSER = "/app/bin/data_parser"
IN_DIR = "/app/data/in"
OUT_DIR = "/app/data/out"


def run_wrapper(args, timeout=4):
    return subprocess.run([WRAPPER] + args, capture_output=True, text=True, timeout=timeout)


def write_input(path, content, sidecar=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(content)
    if sidecar is not None:
        with open(path + ".sha256", "w", encoding="ascii") as f:
            f.write(sidecar)


def valid_sidecar(content):
    return hashlib.sha256(content).hexdigest() + "\n"


def assert_error(args, code, message):
    result = run_wrapper(args)
    assert result.returncode == code, (args, result.returncode, result.stderr)
    assert message in result.stderr, (args, result.stderr)


def build_probe_parser(path, token):
    source = r'''
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/seccomp.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *token = "TOKEN_PLACEHOLDER";

static int seccomp_mode(void) {
    FILE *f = fopen("/proc/self/status", "r");
    char line[256];
    int mode = -1;
    if (!f) return -1;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "Seccomp:%d", &mode) == 1) break;
    }
    fclose(f);
    return mode;
}

static void report(const char *out, const char *kind, int value) {
    FILE *f = fopen(out, "w");
    if (!f) _exit(111);
    fprintf(f, "%s %s %d\n", token, kind, value);
    fclose(f);
}

int main(int argc, char **argv) {
    char mode[64] = {0};
    FILE *in;
    long r = -1;
    int saved_errno;
    if (argc != 3) return 112;
    in = fopen(argv[1], "r");
    if (!in) return 113;
    if (!fgets(mode, sizeof(mode), in)) mode[0] = '\0';
    fclose(in);
    mode[strcspn(mode, "\r\n")] = '\0';

    if (!strcmp(mode, "BASIC")) {
        FILE *out = fopen(argv[2], "w");
        int nnp = prctl(PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0);
        int sec = seccomp_mode();
        if (!out) return 114;
        fprintf(out, "%s BASIC nnp=%d seccomp=%d argc=%d in=%s out=%s\n",
                token, nnp, sec, argc, argv[1], argv[2]);
        fclose(out);
        return 23;
    }

    errno = 0;
    if (!strcmp(mode, "socket")) {
        r = syscall(SYS_socket, AF_INET, SOCK_STREAM, 0);
        if (r >= 0) close((int)r);
    } else if (!strcmp(mode, "connect")) {
        struct sockaddr_in a;
        memset(&a, 0, sizeof(a));
        a.sin_family = AF_INET;
        r = syscall(SYS_connect, -1, &a, sizeof(a));
    } else if (!strcmp(mode, "bind")) {
        struct sockaddr_in a;
        memset(&a, 0, sizeof(a));
        a.sin_family = AF_INET;
        r = syscall(SYS_bind, -1, &a, sizeof(a));
    } else if (!strcmp(mode, "listen")) {
        r = syscall(SYS_listen, -1, 1);
    } else if (!strcmp(mode, "accept")) {
        r = syscall(SYS_accept, -1, NULL, NULL);
    } else if (!strcmp(mode, "clone")) {
        r = syscall(SYS_clone, SIGCHLD, 0, 0, 0, 0);
        if (r == 0) _exit(0);
        if (r > 0) waitpid((pid_t)r, NULL, 0);
    } else {
        return 115;
    }
    saved_errno = errno;

    if (r >= 0) {
        report(argv[2], "ALLOWED", 0);
        return 90;
    }
    if (saved_errno == EPERM || saved_errno == EACCES || saved_errno == ENOSYS) {
        report(argv[2], "DENIED", saved_errno);
        return 40;
    }
    report(argv[2], "NOT_FILTERED", saved_errno);
    return 91;
}
'''.replace("TOKEN_PLACEHOLDER", token)
    src = "/tmp/probe_parser.c"
    with open(src, "w", encoding="utf-8") as f:
        f.write(source)
    subprocess.run(["gcc", "-O2", "-Wall", "-Wextra", "-o", path, src], check=True)
    os.chmod(path, 0o755)


def test_secure_wrapper_accuracy():
    assert os.path.isfile(SOURCE), f"Wrapper source not found at {SOURCE}"
    assert os.path.isfile(WRAPPER), f"Wrapper binary not found at {WRAPPER}"
    assert os.access(WRAPPER, os.X_OK), f"Wrapper binary at {WRAPPER} is not executable"
    with open(WRAPPER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "secure_wrapper must be a compiled executable"

    os.makedirs(IN_DIR, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs("/tmp/malicious", exist_ok=True)

    nonce = secrets.token_hex(12)
    token = secrets.token_hex(24)
    probe = "/tmp/probe_data_parser"
    backup = "/tmp/original_data_parser_" + nonce
    build_probe_parser(probe, token)
    shutil.move(PARSER, backup)
    shutil.copy2(probe, PARSER)
    os.chmod(PARSER, 0o755)

    try:
        # Exactly two wrapper arguments are required.
        assert run_wrapper([]).returncode != 0
        assert run_wrapper(["/app/data/in/only-one"]).returncode != 0
        assert run_wrapper(["a", "b", "c"]).returncode != 0

        # Original path-policy assertions, using fresh unpredictable paths and
        # valid integrity metadata so integrity verification can happen first.
        external_in = "/tmp/malicious/in_" + nonce
        external_data = b"external-" + secrets.token_bytes(17)
        write_input(external_in, external_data, valid_sidecar(external_data))
        assert_error([external_in, OUT_DIR + "/out_" + nonce], 1, "POLICY_VIOLATION")

        policy_input = IN_DIR + "/policy_" + nonce
        policy_data = b"BASIC\n"
        write_input(policy_input, policy_data, valid_sidecar(policy_data))
        assert_error([policy_input, "/tmp/malicious/out_" + nonce], 1, "POLICY_VIOLATION")
        assert_error([policy_input, "/app/data/outside_" + nonce], 1, "POLICY_VIOLATION")

        near_prefix = "/app/data/in_evil/file_" + nonce
        os.makedirs(os.path.dirname(near_prefix), exist_ok=True)
        write_input(near_prefix, policy_data, valid_sidecar(policy_data))
        assert_error([near_prefix, OUT_DIR + "/near_" + nonce], 1, "POLICY_VIOLATION")

        # Preserve the integrity-failure assertion and exercise missing,
        # mismatched, and non-exact sidecar contents.
        bad = IN_DIR + "/bad_" + nonce
        bad_data = secrets.token_bytes(41)
        write_input(bad, bad_data, "0" * 64 + "\n")
        assert_error([bad, OUT_DIR + "/badout_" + nonce], 2, "INTEGRITY_ERROR")

        missing = IN_DIR + "/missing_" + nonce
        missing_data = secrets.token_bytes(29)
        write_input(missing, missing_data, None)
        assert_error([missing, OUT_DIR + "/missingout_" + nonce], 2, "INTEGRITY_ERROR")

        malformed = IN_DIR + "/malformed_" + nonce
        malformed_data = secrets.token_bytes(33)
        write_input(malformed, malformed_data, valid_sidecar(malformed_data) + "extra\n")
        assert_error([malformed, OUT_DIR + "/malformedout_" + nonce], 2, "INTEGRITY_ERROR")

        # Integrity must precede output-path policy checking.
        priority = IN_DIR + "/priority_" + nonce
        priority_data = secrets.token_bytes(37)
        write_input(priority, priority_data, "f" * 64 + "\n")
        result = run_wrapper([priority, "/tmp/malicious/priority_" + nonce])
        assert result.returncode == 2, (result.returncode, result.stderr)
        assert "INTEGRITY_ERROR" in result.stderr

        # A valid input must actually execute the parser, pass both exact
        # arguments, install seccomp, set NO_NEW_PRIVS, and propagate status.
        good = IN_DIR + "/good_" + nonce
        good_out = OUT_DIR + "/good_" + nonce
        good_data = b"BASIC\n"
        write_input(good, good_data, valid_sidecar(good_data))
        result = run_wrapper([good, good_out])
        assert result.returncode == 23, (result.returncode, result.stderr)
        assert "POLICY_VIOLATION" not in result.stderr
        assert "INTEGRITY_ERROR" not in result.stderr
        with open(good_out, "r", encoding="utf-8") as f:
            report = f.read()
        assert token in report and "BASIC" in report
        assert "nnp=1" in report, report
        assert "seccomp=2" in report, report
        assert "argc=3" in report and ("in=" + good) in report and ("out=" + good_out) in report

        # Check every syscall explicitly required by the instruction. If a
        # kill action is used, no report may be produced and the status must
        # be nonzero; errno-based filters must produce the DENIED report and
        # have their child status propagated exactly.
        for syscall_name in ("socket", "connect", "bind", "listen", "accept", "clone"):
            inp = IN_DIR + "/probe_" + syscall_name + "_" + nonce
            out = OUT_DIR + "/probe_" + syscall_name + "_" + nonce
            content = (syscall_name + "\n").encode("ascii")
            write_input(inp, content, valid_sidecar(content))
            if os.path.exists(out):
                os.unlink(out)
            result = run_wrapper([inp, out])
            assert result.returncode != 0, (syscall_name, result.returncode, result.stderr)
            if os.path.exists(out):
                with open(out, "r", encoding="utf-8") as f:
                    syscall_report = f.read()
                assert token in syscall_report, (syscall_name, syscall_report)
                assert "DENIED" in syscall_report, (syscall_name, syscall_report)
                assert "ALLOWED" not in syscall_report and "NOT_FILTERED" not in syscall_report
                assert result.returncode == 40, (syscall_name, result.returncode)
    finally:
        if os.path.exists(PARSER):
            os.unlink(PARSER)
        shutil.move(backup, PARSER)

PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
