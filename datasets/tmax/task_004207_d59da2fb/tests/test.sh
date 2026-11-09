#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid

EXPECTED_SOURCE = '''#include <stdio.h>
#include <string.h>
#include <stdlib.h>

struct AuthContext {
    char username[64];
    int is_admin;
};

void process_rotation(const char *cert_path) {
    char command[256];
    // Computes the file integrity hash of the new cert
    snprintf(command, sizeof(command), "sha256sum %s > /home/user/rotation_success.log", cert_path);
    system(command);
    printf("Credential rotation successful.\\n");
}

int main(int argc, char *argv[]) {
    if (argc != 3) {
        printf("Usage: %s <username> <cert_path>\\n", argv[0]);
        return 1;
    }

    struct AuthContext ctx;
    ctx.is_admin = 0;

    // Vulnerability: Unbounded strcpy into a 64-byte buffer
    strcpy(ctx.username, argv[1]);

    if (strcmp(ctx.username, "admin") == 0) {
        printf("Admin password required (prompt disabled in legacy mode).\\n");
        return 1;
    }

    if (ctx.is_admin != 0) {
        process_rotation(argv[2]);
    } else {
        printf("Authentication failed. Access denied.\\n");
    }

    return 0;
}
'''


def run_checked(args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {args!r}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_new_cert_exists_and_is_pem():
    cert_path = "/home/user/new_cert.pem"
    assert os.path.exists(cert_path), f"{cert_path} does not exist."
    assert os.path.isfile(cert_path), f"{cert_path} is not a file."

    with open(cert_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    assert "-----BEGIN CERTIFICATE-----" in content, f"{cert_path} does not appear to contain a valid PEM certificate."

    run_checked(["openssl", "x509", "-in", cert_path, "-noout"])
    run_checked(["openssl", "x509", "-in", cert_path, "-checkend", "0", "-noout"])
    text = run_checked(["openssl", "x509", "-in", cert_path, "-noout", "-text"]).stdout
    assert re.search(r"Public Key Algorithm:\s*rsaEncryption", text), "Certificate public key is not RSA."
    assert re.search(r"Public-Key:\s*\(2048 bit\)", text), "Certificate RSA key is not 2048 bits."
    run_checked(["openssl", "verify", "-CAfile", cert_path, cert_path])


def test_exploit_c_exists():
    exploit_path = "/home/user/exploit.c"
    assert os.path.exists(exploit_path), f"{exploit_path} does not exist."
    assert os.path.isfile(exploit_path), f"{exploit_path} is not a file."


def test_exploit_compiles_invokes_checker_and_exploits_overflow():
    exploit_path = "/home/user/exploit.c"
    checker_path = "/home/user/auth_checker"
    checker_source = "/home/user/auth_checker.c"
    cert_path = "/home/user/new_cert.pem"
    log_path = "/home/user/rotation_success.log"

    with open(checker_source, "r", encoding="utf-8") as f:
        assert f.read() == EXPECTED_SOURCE, "auth_checker.c was modified."

    work = tempfile.mkdtemp(prefix="verify_rotation_")
    real_checker = os.path.join(work, "real_auth_checker")
    wrapper_bin = os.path.join(work, "auth_wrapper")
    wrapper_src = os.path.join(work, "wrapper.c")
    exploit_bin = os.path.join(work, "exploit")
    marker = os.path.join(work, "invocation_" + uuid.uuid4().hex)
    reference_dir = os.path.join(work, "reference")
    os.mkdir(reference_dir)
    reference_source = os.path.join(reference_dir, "auth_checker.c")
    reference_binary = os.path.join(reference_dir, "auth_checker")

    try:
        with open(reference_source, "w", encoding="utf-8") as f:
            f.write(EXPECTED_SOURCE)
        run_checked(["gcc", "-O0", "-fno-stack-protector", "-o", reference_binary, reference_source])
        assert filecmp.cmp(checker_path, reference_binary, shallow=False), "auth_checker binary was modified or recompiled."

        run_checked(["gcc", "-O0", "-o", exploit_bin, exploit_path])

        wrapper_code = f'''#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {{
    const char *real_checker = {json.dumps(real_checker)};
    const char *marker = {json.dumps(marker)};
    const char *cert = "/home/user/new_cert.pem";
    const char *log = "/home/user/rotation_success.log";

    if (argc != 3 || strcmp(argv[2], cert) != 0 || strcmp(argv[1], "admin") == 0 || strlen(argv[1]) <= 64) {{
        return 97;
    }}

    unlink(log);
    pid_t pid = fork();
    if (pid < 0) return 98;
    if (pid == 0) {{
        execv(real_checker, argv);
        _exit(99);
    }}

    int status = 0;
    if (waitpid(pid, &status, 0) != pid || !WIFEXITED(status) || WEXITSTATUS(status) != 0) return 100;

    struct stat st;
    if (stat(log, &st) != 0 || !S_ISREG(st.st_mode)) return 101;
    int fd = open(marker, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0) return 102;
    if (write(fd, "ok\\n", 3) != 3) {{ close(fd); return 103; }}
    close(fd);
    return 0;
}}
'''
        with open(wrapper_src, "w", encoding="utf-8") as f:
            f.write(wrapper_code)
        run_checked(["gcc", "-O0", "-o", wrapper_bin, wrapper_src])

        os.replace(checker_path, real_checker)
        os.replace(wrapper_bin, checker_path)
        os.chmod(checker_path, 0o755)
        if os.path.exists(log_path):
            os.unlink(log_path)

        result = subprocess.run([exploit_bin], cwd="/home/user", stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, timeout=15)
        assert result.returncode == 0, (
            f"Compiled exploit failed with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(marker), (
            "The exploit did not invoke /home/user/auth_checker with the certificate path "
            "and an overflowing username payload."
        )
        assert filecmp.cmp(real_checker, reference_binary, shallow=False), "The original auth_checker was modified during exploitation."
        with open(checker_source, "r", encoding="utf-8") as f:
            assert f.read() == EXPECTED_SOURCE, "auth_checker.c was modified during exploitation."
    finally:
        if os.path.exists(real_checker):
            try:
                if os.path.lexists(checker_path):
                    os.unlink(checker_path)
                os.replace(real_checker, checker_path)
                os.chmod(checker_path, 0o777)
            except OSError:
                pass
        shutil.rmtree(work, ignore_errors=True)


def test_rotation_success_log_exists_and_correct():
    log_path = "/home/user/rotation_success.log"
    cert_path = "/home/user/new_cert.pem"

    assert os.path.exists(log_path), f"{log_path} does not exist. The exploit may not have succeeded."
    assert os.path.isfile(log_path), f"{log_path} is not a file."
    assert os.path.exists(cert_path), f"Cannot verify {log_path} because {cert_path} is missing."

    # Compute the actual SHA-256 hash of the certificate
    with open(cert_path, "rb") as f:
        cert_data = f.read()
    expected_hash = hashlib.sha256(cert_data).hexdigest()

    # Read the log file
    with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
        log_content = f.read().strip()

    # The log was generated by `sha256sum`, so it should start with the 64-character hex hash
    match = re.search(r'^([a-fA-F0-9]{64})', log_content)
    assert match is not None, f"Could not find a valid 64-character SHA256 hash at the beginning of {log_path}."

    actual_hash = match.group(1).lower()
    assert actual_hash == expected_hash, (
        f"The hash in {log_path} ({actual_hash}) does not match the actual SHA-256 hash "
        f"of {cert_path} ({expected_hash})."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
