#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import ssl
import socket
import subprocess
import tempfile
import urllib.request
import pytest

HOME = "/home/user"
SRC = HOME + "/secure_audit.c"
BIN = HOME + "/secure_audit"
KEYFILE = HOME + "/audit_key.txt"
ENCFILE = HOME + "/audit_trail.enc"
CERT = HOME + "/certs/audit_cert.pem"
PRIVKEY = HOME + "/certs/audit_key.pem"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(cmd, **kwargs)


def read_key_iv():
    with open(KEYFILE, "r", encoding="ascii") as f:
        content = f.read()
    key_match = re.search(r"^KEY:\s*([0-9a-fA-F]{64})$", content, re.MULTILINE)
    iv_match = re.search(r"^IV:\s*([0-9a-fA-F]{32})$", content, re.MULTILINE)
    assert key_match is not None, "KEY not found or not 64 hex characters in audit_key.txt."
    assert iv_match is not None, "IV not found or not 32 hex characters in audit_key.txt."
    assert re.fullmatch(r"KEY: [0-9a-fA-F]{64}\nIV: [0-9a-fA-F]{32}\n?", content), \
        "audit_key.txt does not have the required exact format."
    return key_match.group(1), iv_match.group(1)


def decrypt(path, key, iv):
    result = subprocess.run([
        "openssl", "enc", "-d", "-aes-256-cbc", "-K", key, "-iv", iv,
        "-in", path
    ], capture_output=True, timeout=20)
    assert result.returncode == 0, "Decryption failed: " + result.stderr.decode(errors="replace")
    return result.stdout


def build_trace_library(tmpdir):
    source = os.path.join(tmpdir, "trace.c")
    library = os.path.join(tmpdir, "trace.so")
    code = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <openssl/evp.h>
#include <openssl/params.h>

static void mark(const char *s) {
    const char *p = getenv("AUDIT_EVP_TRACE");
    if (!p) return;
    int fd = open(p, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) { write(fd, s, __builtin_strlen(s)); close(fd); }
}

int EVP_EncryptInit_ex(EVP_CIPHER_CTX *c, const EVP_CIPHER *t, ENGINE *e,
                       const unsigned char *k, const unsigned char *v) {
    static int (*real)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *, const unsigned char *, const unsigned char *);
    if (!real) real = dlsym(RTLD_NEXT, "EVP_EncryptInit_ex");
    mark("INIT\n"); return real(c, t, e, k, v);
}
int EVP_EncryptInit_ex2(EVP_CIPHER_CTX *c, const EVP_CIPHER *t,
                        const unsigned char *k, const unsigned char *v,
                        const OSSL_PARAM p[]) {
    static int (*real)(EVP_CIPHER_CTX *, const EVP_CIPHER *, const unsigned char *, const unsigned char *, const OSSL_PARAM []);
    if (!real) real = dlsym(RTLD_NEXT, "EVP_EncryptInit_ex2");
    mark("INIT\n"); return real(c, t, k, v, p);
}
int EVP_EncryptUpdate(EVP_CIPHER_CTX *c, unsigned char *o, int *ol,
                      const unsigned char *i, int il) {
    static int (*real)(EVP_CIPHER_CTX *, unsigned char *, int *, const unsigned char *, int);
    if (!real) real = dlsym(RTLD_NEXT, "EVP_EncryptUpdate");
    mark("UPDATE\n"); return real(c, o, ol, i, il);
}
int EVP_EncryptFinal_ex(EVP_CIPHER_CTX *c, unsigned char *o, int *ol) {
    static int (*real)(EVP_CIPHER_CTX *, unsigned char *, int *);
    if (!real) real = dlsym(RTLD_NEXT, "EVP_EncryptFinal_ex");
    mark("FINAL\n"); return real(c, o, ol);
}
int EVP_CipherInit_ex(EVP_CIPHER_CTX *c, const EVP_CIPHER *t, ENGINE *e,
                      const unsigned char *k, const unsigned char *v, int enc) {
    static int (*real)(EVP_CIPHER_CTX *, const EVP_CIPHER *, ENGINE *, const unsigned char *, const unsigned char *, int);
    if (!real) real = dlsym(RTLD_NEXT, "EVP_CipherInit_ex");
    mark("INIT\n"); return real(c, t, e, k, v, enc);
}
int EVP_CipherInit_ex2(EVP_CIPHER_CTX *c, const EVP_CIPHER *t,
                       const unsigned char *k, const unsigned char *v,
                       int enc, const OSSL_PARAM p[]) {
    static int (*real)(EVP_CIPHER_CTX *, const EVP_CIPHER *, const unsigned char *, const unsigned char *, int, const OSSL_PARAM []);
    if (!real) real = dlsym(RTLD_NEXT, "EVP_CipherInit_ex2");
    mark("INIT\n"); return real(c, t, k, v, enc, p);
}
int EVP_CipherUpdate(EVP_CIPHER_CTX *c, unsigned char *o, int *ol,
                     const unsigned char *i, int il) {
    static int (*real)(EVP_CIPHER_CTX *, unsigned char *, int *, const unsigned char *, int);
    if (!real) real = dlsym(RTLD_NEXT, "EVP_CipherUpdate");
    mark("UPDATE\n"); return real(c, o, ol, i, il);
}
int EVP_CipherFinal_ex(EVP_CIPHER_CTX *c, unsigned char *o, int *ol) {
    static int (*real)(EVP_CIPHER_CTX *, unsigned char *, int *);
    if (!real) real = dlsym(RTLD_NEXT, "EVP_CipherFinal_ex");
    mark("FINAL\n"); return real(c, o, ol);
}
'''
    with open(source, "w") as f:
        f.write(code)
    result = run(["gcc", "-shared", "-fPIC", source, "-o", library, "-ldl"])
    assert result.returncode == 0, "Failed to build EVP tracing library: " + result.stderr
    return library


def test_secure_audit_c_exists_and_builds():
    assert os.path.isfile(SRC), "/home/user/secure_audit.c does not exist."
    with open(SRC, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bEVP_(?:Encrypt|Cipher)Init_ex2?\s*\(", source), "Source does not initialize encryption through EVP."
    assert re.search(r"\bEVP_(?:Encrypt|Cipher)Update\s*\(", source), "Source does not encrypt data through EVP update."
    assert re.search(r"\bEVP_(?:Encrypt|Cipher)Final_ex\s*\(", source), "Source does not finalize encryption through EVP."
    assert not re.search(r"\b(?:system|popen|execl|execle|execlp|execv|execve|execvp|posix_spawn|posix_spawnp)\s*\(", source), \
        "The auditing tool must perform its own scan and EVP encryption, not invoke external commands."
    result = run(["gcc", "-O2", "-Wall", "-Wextra", SRC, "-o", BIN, "-lssl", "-lcrypto"])
    assert result.returncode == 0, "secure_audit.c failed to compile: " + result.stderr
    assert os.path.isfile(BIN) and os.access(BIN, os.X_OK), "/home/user/secure_audit was not produced as an executable."


def test_program_recursion_sorting_randomness_and_evp_execution():
    with tempfile.TemporaryDirectory(prefix="audit-fixture-") as root, tempfile.TemporaryDirectory(prefix="audit-trace-") as trace_dir:
        nested = os.path.join(root, "nested", "deeper")
        os.makedirs(nested)
        selected = [
            os.path.join(root, "z setuid"),
            os.path.join(root, "nested", "a-setuid"),
            os.path.join(nested, "middle-setuid"),
        ]
        ordinary = os.path.join(root, "nested", "ordinary")
        for path in selected + [ordinary]:
            with open(path, "wb") as f:
                f.write(b"fixture\n")
        for path in selected:
            os.chmod(path, 0o4755)
        os.chmod(ordinary, 0o755)
        os.chmod(os.path.join(root, "nested"), 0o4755)

        trace_lib = build_trace_library(trace_dir)
        trace_file = os.path.join(trace_dir, "calls")
        env = os.environ.copy()
        env["LD_PRELOAD"] = trace_lib
        env["AUDIT_EVP_TRACE"] = trace_file
        first = run([BIN, root], env=env)
        assert first.returncode == 0, "secure_audit failed on recursive fixture: " + first.stderr
        assert os.path.isfile(ENCFILE), "/home/user/audit_trail.enc does not exist."
        first_key, first_iv = read_key_iv()
        expected = "".join(path + "\n" for path in sorted(selected)).encode()
        assert decrypt(ENCFILE, first_key, first_iv) == expected, \
            "Program did not recursively collect exactly the sorted setuid regular files."
        with open(trace_file, "r") as f:
            calls = f.read()
        assert "INIT\n" in calls and "UPDATE\n" in calls and "FINAL\n" in calls, \
            "The executed program did not perform encryption through the OpenSSL EVP API."

        second = run([BIN, root])
        assert second.returncode == 0, "secure_audit failed on its second execution: " + second.stderr
        second_key, second_iv = read_key_iv()
        assert first_key != second_key, "The program reused its 256-bit key instead of generating a fresh random key."
        assert first_iv != second_iv, "The program reused its IV instead of generating a fresh random IV."
        assert decrypt(ENCFILE, second_key, second_iv) == expected


def test_execute_required_usr_bin_audit():
    result = run([BIN, "/usr/bin"])
    assert result.returncode == 0, "secure_audit failed when executed against /usr/bin: " + result.stderr
    assert os.path.isfile(KEYFILE)
    assert os.path.isfile(ENCFILE), "/home/user/audit_trail.enc does not exist."
    key, iv = read_key_iv()
    find_result = subprocess.run("find /usr/bin -type f -perm -4000 | sort", shell=True, capture_output=True, timeout=20)
    assert find_result.returncode == 0, "Failed to run find command for expected output."
    assert decrypt(ENCFILE, key, iv) == find_result.stdout, \
        "Decrypted text does not match expected setuid files list."


def test_certificates_are_required_rsa_pair():
    assert os.path.isfile(CERT), "/home/user/certs/audit_cert.pem does not exist."
    assert os.path.isfile(PRIVKEY), "/home/user/certs/audit_key.pem does not exist."
    with open(PRIVKEY, "r", errors="replace") as f:
        key_pem = f.read()
    assert "ENCRYPTED" not in key_pem and "Proc-Type: 4,ENCRYPTED" not in key_pem, \
        "The TLS private key is encrypted; an unencrypted key was required."

    key_info = run(["openssl", "pkey", "-in", PRIVKEY, "-noout", "-text", "-passin", "pass:"])
    assert key_info.returncode == 0, "TLS private key is invalid or requires a passphrase: " + key_info.stderr
    assert re.search(r"Private-Key:\s*\(2048 bit", key_info.stdout), "TLS private key is not RSA-2048."

    cert_info = run(["openssl", "x509", "-in", CERT, "-noout", "-subject", "-nameopt", "RFC2253"])
    assert cert_info.returncode == 0, "TLS certificate is invalid: " + cert_info.stderr
    subject = cert_info.stdout.strip().removeprefix("subject=")
    assert re.search(r"(?:^|,)CN=localhost(?:,|$)", subject), "Certificate Common Name is not localhost."

    verify = run(["openssl", "verify", "-CAfile", CERT, CERT])
    assert verify.returncode == 0, "Certificate is not valid as a self-signed certificate: " + verify.stderr
    cert_pub = run(["openssl", "x509", "-in", CERT, "-pubkey", "-noout"])
    key_pub = run(["openssl", "pkey", "-in", PRIVKEY, "-pubout", "-passin", "pass:"])
    assert cert_pub.returncode == 0 and key_pub.returncode == 0
    assert cert_pub.stdout == key_pub.stdout, "Certificate and private key do not correspond."


def find_s_server():
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if len(argv) < 2 or os.path.basename(argv[0]) != "openssl" or argv[1] != "s_server":
                continue
            if "-WWW" not in argv:
                continue
            if "-accept" not in argv:
                continue
            accept = argv[argv.index("-accept") + 1]
            if "8443" not in accept:
                continue
            if os.path.realpath(f"/proc/{name}/cwd") != HOME:
                continue
            return int(name)
        except (OSError, ValueError, IndexError):
            pass
    return None


def test_tls_server_and_decryption():
    pid = find_s_server()
    assert pid is not None, "No openssl s_server -WWW process serving /home/user on port 8443 was found."

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with socket.create_connection(("localhost", 8443), timeout=5) as raw:
            with ctx.wrap_socket(raw, server_hostname="localhost") as tls:
                served_der = tls.getpeercert(binary_form=True)
        with open(CERT, "r") as f:
            expected_der = ssl.PEM_cert_to_DER_cert(f.read())
        assert served_der == expected_der, "The TLS server is not using audit_cert.pem."

        with urllib.request.urlopen("https://localhost:8443/audit_trail.enc", context=ctx, timeout=5) as response:
            assert response.status == 200, f"HTTP status code {response.status}"
            encrypted_data = response.read()
    except Exception as e:
        pytest.fail(f"Failed to download from https://localhost:8443/audit_trail.enc: {e}")

    with open(ENCFILE, "rb") as f:
        assert encrypted_data == f.read(), "TLS server did not serve /home/user/audit_trail.enc."
    downloaded = "/tmp/downloaded_audit_trail.enc"
    with open(downloaded, "wb") as f:
        f.write(encrypted_data)
    key, iv = read_key_iv()
    decrypted = decrypt(downloaded, key, iv)
    expected = subprocess.run("find /usr/bin -type f -perm -4000 | sort", shell=True, capture_output=True, timeout=20)
    assert expected.returncode == 0, "Failed to run find command for expected output."
    assert decrypted == expected.stdout, "Decrypted text does not match expected setuid files list."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
