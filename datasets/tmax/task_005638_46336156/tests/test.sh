#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PRELOAD_EOF' > /tmp/fake_urandom.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static unsigned char marked[65536];
static size_t offsets[65536];

static void mark_fd(int fd) {
    if (fd >= 0 && fd < (int)sizeof(marked)) {
        marked[fd] = 1;
        offsets[fd] = 0;
    }
}

int open(const char *path, int flags, ...) {
    static int (*real_open)(const char *, int, ...) = NULL;
    if (!real_open) real_open = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    int fd = (flags & O_CREAT) ? real_open(path, flags, mode) : real_open(path, flags);
    if (path && strcmp(path, "/dev/urandom") == 0) mark_fd(fd);
    return fd;
}

int open64(const char *path, int flags, ...) {
    static int (*real_open64)(const char *, int, ...) = NULL;
    if (!real_open64) real_open64 = dlsym(RTLD_NEXT, "open64");
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, mode_t);
        va_end(ap);
    }
    int fd = (flags & O_CREAT) ? real_open64(path, flags, mode) : real_open64(path, flags);
    if (path && strcmp(path, "/dev/urandom") == 0) mark_fd(fd);
    return fd;
}

FILE *fopen(const char *path, const char *mode) {
    static FILE *(*real_fopen)(const char *, const char *) = NULL;
    if (!real_fopen) real_fopen = dlsym(RTLD_NEXT, "fopen");
    FILE *fp = real_fopen(path, mode);
    if (fp && path && strcmp(path, "/dev/urandom") == 0) mark_fd(fileno(fp));
    return fp;
}

FILE *fopen64(const char *path, const char *mode) {
    static FILE *(*real_fopen64)(const char *, const char *) = NULL;
    if (!real_fopen64) real_fopen64 = dlsym(RTLD_NEXT, "fopen64");
    FILE *fp = real_fopen64(path, mode);
    if (fp && path && strcmp(path, "/dev/urandom") == 0) mark_fd(fileno(fp));
    return fp;
}

ssize_t read(int fd, void *buf, size_t count) {
    static ssize_t (*real_read)(int, void *, size_t) = NULL;
    if (!real_read) real_read = dlsym(RTLD_NEXT, "read");
    if (fd >= 0 && fd < (int)sizeof(marked) && marked[fd]) {
        unsigned char *out = buf;
        for (size_t i = 0; i < count; i++) out[i] = (unsigned char)((offsets[fd] + i) & 0xff);
        offsets[fd] += count;
        return (ssize_t)count;
    }
    return real_read(fd, buf, count);
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream) {
    static size_t (*real_fread)(void *, size_t, size_t, FILE *) = NULL;
    if (!real_fread) real_fread = dlsym(RTLD_NEXT, "fread");
    int fd = fileno(stream);
    if (fd >= 0 && fd < (int)sizeof(marked) && marked[fd]) {
        size_t count = size * nmemb;
        unsigned char *out = ptr;
        for (size_t i = 0; i < count; i++) out[i] = (unsigned char)((offsets[fd] + i) & 0xff);
        offsets[fd] += count;
        return nmemb;
    }
    return real_fread(ptr, size, nmemb, stream);
}
PRELOAD_EOF

gcc -shared -fPIC -O2 -o /tmp/libfake_urandom.so /tmp/fake_urandom.c -ldl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import signal
import socket
import subprocess
import time

VULNERABLE = "/home/user/auth_server_vulnerable"
FIXED = "/home/user/auth_server_fixed"
SOURCE = "/home/user/auth_server.c"
SCRIPT = "/home/user/test_vulns.py"
REBUILT = "/tmp/auth_server_rebuilt"
ARTIFACT_BINARIES = {VULNERABLE, FIXED}


def artifact_processes():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            exe = os.path.realpath(f"/proc/{entry}/exe")
        except OSError:
            continue
        if exe in ARTIFACT_BINARIES:
            found.append(int(entry))
    return found


def stop_artifact_processes():
    pids = artifact_processes()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and artifact_processes():
        time.sleep(0.05)
    for pid in artifact_processes():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def start_server(binary, env=None):
    port = free_port()
    proc = subprocess.Popen(
        [binary, str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        env=env, start_new_session=True
    )
    deadline = time.time() + 4
    while time.time() < deadline:
        if proc.poll() is not None:
            stderr = proc.stderr.read().decode(errors="replace")
            raise AssertionError(f"{binary} exited before accepting connections: {stderr}")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                return proc, port
        except OSError:
            time.sleep(0.05)
    proc.terminate()
    raise AssertionError(f"{binary} did not start listening")


def stop_server(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def raw_get(port, target):
    request = f"GET {target} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".encode()
    chunks = []
    with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
        sock.sendall(request)
        sock.settimeout(2)
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks).decode("latin1")


def header(response, name):
    head = response.split("\r\n\r\n", 1)[0]
    for line in head.split("\r\n")[1:]:
        key, sep, value = line.partition(":")
        if sep and key.lower() == name.lower():
            return value.strip()
    return None


def token_from(response):
    cookie = header(response, "Set-Cookie")
    assert cookie is not None and cookie.startswith("AuthToken="), response
    return cookie[len("AuthToken="):].split(";", 1)[0]


def assert_binary(path):
    assert os.path.isfile(path), f"Required compiled binary {path} is missing"
    assert os.access(path, os.X_OK), f"Required binary {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary"


def exercise_vulnerable(binary):
    proc, port = start_server(binary)
    try:
        target = "/login?username=admin&password=test&next=http://malicious.example.com"
        first = raw_get(port, target)
        second = raw_get(port, target)
        assert header(first, "Location") == "http://malicious.example.com"
        assert token_from(first) == token_from(second), "The supplied vulnerable server is not predictably generating the same token"
        payload = "<script>alert(1)</script>"
        rotate = raw_get(port, "/rotate?user=" + payload)
        assert payload in rotate, "The vulnerable server did not reflect the XSS payload"
    finally:
        stop_server(proc)


def exercise_fixed(binary):
    proc, port = start_server(binary)
    try:
        external = raw_get(port, "/login?username=admin&password=test&next=http://malicious.example.com")
        assert header(external, "Location") == "/dashboard", "Absolute redirect was not rejected"
        protocol_relative = raw_get(port, "/login?username=admin&password=test&next=//malicious.example.com")
        assert header(protocol_relative, "Location") == "/dashboard", "Protocol-relative redirect was not rejected"
        relative = raw_get(port, "/login?username=admin&password=test&next=/safe/path")
        assert header(relative, "Location") == "/safe/path", "A valid relative redirect was not preserved"

        tokens = []
        for _ in range(6):
            response = raw_get(port, "/login?username=admin&password=test&next=/dashboard")
            token = token_from(response)
            assert re.fullmatch(r"[0-9a-fA-F]{32}", token), "AuthToken must hex-encode exactly 16 bytes"
            tokens.append(token)
        assert len(set(tokens)) == len(tokens), "AuthToken values repeat across independent login requests"

        payload = "<script>alert(1)</script>"
        rotate = raw_get(port, "/rotate?user=" + payload)
        body = rotate.split("\r\n\r\n", 1)[-1]
        assert payload not in body, "Raw XSS payload was reflected"
        assert "&lt;script&gt;alert(1)&lt;/script&gt;" in body, "Username was not HTML-entity encoded"
    finally:
        stop_server(proc)


def assert_urandom_bytes_drive_token(binary):
    env = os.environ.copy()
    env["LD_PRELOAD"] = "/tmp/libfake_urandom.so"
    proc, port = start_server(binary, env=env)
    try:
        response = raw_get(port, "/login?username=admin&password=test&next=/dashboard")
        token = token_from(response).lower()
        assert token == "000102030405060708090a0b0c0d0e0f", (
            "AuthToken was not produced by reading and hex-encoding 16 bytes from /dev/urandom"
        )
    finally:
        stop_server(proc)


def test_required_artifacts_and_execute_exploit_script():
    assert os.path.isfile(SCRIPT), f"Required exploit script {SCRIPT} is missing"
    assert_binary(VULNERABLE)
    assert_binary(FIXED)
    subprocess.run(["python3", "-m", "py_compile", SCRIPT], check=True, timeout=10)

    stop_artifact_processes()
    for path in ("/home/user/exploit_results.txt", "/home/user/fixed_results.txt"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    try:
        completed = subprocess.run(
            ["python3", SCRIPT], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40
        )
        assert completed.returncode == 0, (
            f"Exploit script failed with exit code {completed.returncode}.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        time.sleep(0.25)
        assert not artifact_processes(), "The exploit script left an authentication server running"
    finally:
        stop_artifact_processes()


def test_exploit_results_file():
    """Verify that the exploit script successfully ran against the vulnerable server."""
    file_path = "/home/user/exploit_results.txt"
    assert os.path.isfile(file_path), f"Expected result file {file_path} does not exist. Did the exploit script run?"
    with open(file_path, "r") as f:
        content = f.read().strip()
    expected_content = "VULNERABLE: OPEN_REDIRECT, XSS, FORGED_TOKEN"
    assert expected_content in content, (
        f"File {file_path} does not contain the expected success string. "
        f"Expected '{expected_content}', but got '{content}'."
    )


def test_fixed_results_file():
    """Verify that the exploit script failed against the patched server."""
    file_path = "/home/user/fixed_results.txt"
    assert os.path.isfile(file_path), f"Expected result file {file_path} does not exist. Did the script run against the patched server?"
    with open(file_path, "r") as f:
        content = f.read().strip()
    expected_content = "SECURE: EXPLOITS_FAILED"
    assert expected_content in content, (
        f"File {file_path} does not contain the expected success string. "
        f"Expected '{expected_content}', but got '{content}'."
    )


def test_patch_urandom_used():
    """Verify the C server was patched to use /dev/urandom for token generation."""
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "/dev/urandom" in content, (
        "The patched server does not appear to read from '/dev/urandom'. "
        "Token generation must be secured using a cryptographically secure pseudorandom number generator."
    )


def test_patch_open_redirect_fixed():
    """Verify the C server was patched to validate redirect URLs."""
    with open(SOURCE, "r") as f:
        content = f.read()
    has_slash_check = re.search(r"redirect_url\[0\]\s*==\s*'\/'", content) or re.search(r"redirect_url\[0\]\s*!=\s*'\/'", content)
    strstr_check = "strstr" in content and "//" in content
    has_double_slash_check = re.search(r"redirect_url\[1\]\s*==\s*'\/'", content) or strstr_check
    validation_present = has_slash_check or ("/" in content and "redirect_url" in content and ("if" in content or "?" in content))
    assert validation_present, (
        "Could not detect open redirect validation in auth_server.c. "
        "Ensure the code checks that the redirect URL starts with a single '/'."
    )


def test_patch_xss_fixed():
    """Verify the C server was patched to HTML-encode user input to prevent XSS."""
    with open(SOURCE, "r") as f:
        content = f.read()
    has_lt = "&lt;" in content
    has_gt = "&gt;" in content
    assert has_lt and has_gt, (
        "Could not detect HTML entity encoding ('&lt;' and '&gt;') in auth_server.c. "
        "The username must be sanitized before being echoed in the HTTP response."
    )


def test_actual_server_behavior_and_source_build():
    exercise_vulnerable(VULNERABLE)
    exercise_fixed(FIXED)
    assert_urandom_bytes_drive_token(FIXED)

    compiled = subprocess.run(
        ["gcc", "-O2", "-o", REBUILT, SOURCE], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert compiled.returncode == 0, f"Patched source does not compile:\n{compiled.stderr}"
    assert_binary(REBUILT)
    exercise_fixed(REBUILT)
    assert_urandom_bytes_drive_token(REBUILT)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
