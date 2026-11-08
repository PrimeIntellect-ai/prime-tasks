#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import secrets
import shutil
import subprocess
import time
import urllib.error
import urllib.request

import pytest

ORIGINAL_BLOCKED = ["/admin", "/private/", "/api/v1/secret"]
RANDOM_PREFIXES = ["/blocked-" + secrets.token_hex(10) for _ in range(4)]
RANDOM_ALLOWED = "/allowed-" + secrets.token_hex(10)
RANDOM_ERROR = "/error-" + secrets.token_hex(10)
RANDOM_NEAR_MISS = RANDOM_PREFIXES[0][:-1] + ("0" if RANDOM_PREFIXES[0][-1] != "0" else "1")
BACKEND_TOKEN = secrets.token_hex(16)
BACKEND_BODY = "backend-body-" + secrets.token_hex(16)
FFI_LOG = "/tmp/trie_ffi.log"


def test_files_exist():
    assert os.path.isfile("/home/user/trie.c"), "/home/user/trie.c is missing"
    assert os.path.isfile("/home/user/Makefile"), "/home/user/Makefile is missing"
    assert os.path.isfile("/home/user/proxy.py"), "/home/user/proxy.py is missing"


def test_make_and_libtrie():
    # Require make to be capable of creating the requested artifact, rather than
    # accepting an unrelated library left in place before verification.
    try:
        os.remove("/home/user/libtrie.so")
    except FileNotFoundError:
        pass

    result = subprocess.run(["make"], cwd="/home/user", capture_output=True)
    assert result.returncode == 0, f"make failed: {result.stderr.decode()}"
    assert os.path.isfile("/home/user/libtrie.so"), "/home/user/libtrie.so was not built"


def load_trie(lib_path="/home/user/libtrie.so"):
    try:
        trie_lib = ctypes.CDLL(lib_path)
    except OSError as e:
        pytest.fail(f"Failed to load {lib_path}: {e}")

    trie_lib.trie_create.restype = ctypes.c_void_p
    trie_lib.trie_create.argtypes = []
    trie_lib.trie_insert.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    trie_lib.trie_insert.restype = None
    trie_lib.trie_check.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    trie_lib.trie_check.restype = ctypes.c_int
    return trie_lib


def test_trie_c_extension():
    subprocess.run(["make"], cwd="/home/user", capture_output=True)
    lib_path = "/home/user/libtrie.so"
    assert os.path.isfile(lib_path), f"{lib_path} is missing"

    trie_lib = load_trie(lib_path)
    trie = trie_lib.trie_create()
    assert trie is not None, "trie_create returned NULL"

    trie_lib.trie_insert(trie, b"/admin")
    trie_lib.trie_insert(trie, b"/private/")

    assert trie_lib.trie_check(trie, b"/admin") == 1, "trie_check failed to match /admin"
    assert trie_lib.trie_check(trie, b"/admin/dashboard") == 1, "trie_check failed to match prefix /admin/dashboard"
    assert trie_lib.trie_check(trie, b"/private/data") == 1, "trie_check failed to match /private/data"
    assert trie_lib.trie_check(trie, b"/public") == 0, "trie_check incorrectly matched /public"
    assert trie_lib.trie_check(trie, b"/priv") == 0, "trie_check incorrectly matched partial prefix /priv"

    # Exercise prefixes generated only when the verifier runs, including checks
    # before and after insertion and paths not present in the original tests.
    dynamic = trie_lib.trie_create()
    assert dynamic is not None, "trie_create returned NULL for dynamic trie"
    probe = ("/probe-" + secrets.token_hex(12)).encode()
    assert trie_lib.trie_check(dynamic, probe) == 0, "an empty trie matched a random path"

    inserted = []
    for _ in range(20):
        prefix = ("/p-" + secrets.token_hex(12)).encode()
        assert trie_lib.trie_check(dynamic, prefix) == 0, "random prefix matched before insertion"
        trie_lib.trie_insert(dynamic, prefix)
        inserted.append(prefix)
        assert trie_lib.trie_check(dynamic, prefix) == 1, "inserted random prefix did not match"
        assert trie_lib.trie_check(dynamic, prefix + b"/child/" + secrets.token_hex(4).encode()) == 1, "random prefix did not match a longer path"

    for _ in range(20):
        nonmatch = ("/unmatched-" + secrets.token_hex(12)).encode()
        assert not any(nonmatch.startswith(p) for p in inserted)
        assert trie_lib.trie_check(dynamic, nonmatch) == 0, "trie matched an unrelated random path"


def install_logging_wrapper():
    """Wrap the validated agent library so proxy calls through ctypes are observable."""
    agent_lib = "/tmp/libtrie_agent.so"
    shutil.copy2("/home/user/libtrie.so", agent_lib)
    try:
        os.remove(FFI_LOG)
    except FileNotFoundError:
        pass

    wrapper_source = r'''
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef void* (*create_fn)(void);
typedef void (*insert_fn)(void*, const char*);
typedef int (*check_fn)(void*, const char*);

static void *handle;
static create_fn real_create;
static insert_fn real_insert;
static check_fn real_check;

static void init_real(void) {
    if (handle) return;
    handle = dlopen("/tmp/libtrie_agent.so", RTLD_NOW | RTLD_LOCAL);
    if (!handle) abort();
    real_create = (create_fn)dlsym(handle, "trie_create");
    real_insert = (insert_fn)dlsym(handle, "trie_insert");
    real_check = (check_fn)dlsym(handle, "trie_check");
    if (!real_create || !real_insert || !real_check) abort();
}

static void log_call(char kind, const char *value, int result, int has_result) {
    FILE *f = fopen("/tmp/trie_ffi.log", "a");
    if (!f) return;
    if (value) {
        if (has_result) fprintf(f, "%c %s %d\n", kind, value, result);
        else fprintf(f, "%c %s\n", kind, value);
    } else {
        fprintf(f, "%c\n", kind);
    }
    fclose(f);
}

void* trie_create(void) {
    init_real();
    void *result = real_create();
    log_call('C', NULL, 0, 0);
    return result;
}

void trie_insert(void *trie, const char *prefix) {
    init_real();
    real_insert(trie, prefix);
    log_call('I', prefix, 0, 0);
}

int trie_check(void *trie, const char *path) {
    init_real();
    int result = real_check(trie, path);
    log_call('K', path, result, 1);
    return result;
}
'''
    with open("/tmp/trie_wrapper.c", "w") as f:
        f.write(wrapper_source)

    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-O2", "-o", "/tmp/libtrie_wrapper.so", "/tmp/trie_wrapper.c", "-ldl"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"failed to build verifier FFI wrapper: {result.stderr}"
    shutil.copy2("/tmp/libtrie_wrapper.so", "/home/user/libtrie.so")


@pytest.fixture(scope="module")
def servers():
    result = subprocess.run(["make"], cwd="/home/user", capture_output=True)
    assert result.returncode == 0, f"make failed before proxy tests: {result.stderr.decode()}"

    old_blocked = open("/home/user/blocked.txt", "rb").read()
    with open("/home/user/blocked.txt", "w") as f:
        for prefix in ORIGINAL_BLOCKED + RANDOM_PREFIXES:
            f.write(prefix + "\n")

    install_logging_wrapper()

    config = {
        "allowed": RANDOM_ALLOWED,
        "error": RANDOM_ERROR,
        "token": BACKEND_TOKEN,
        "body": BACKEND_BODY,
    }
    with open("/tmp/backend_config.json", "w") as f:
        json.dump(config, f)

    backend_source = r'''
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

with open("/tmp/backend_config.json") as f:
    cfg = json.load(f)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/index.html":
            status, body = 200, b"OK\n"
        elif self.path == "/public.txt":
            status, body = 200, b"PUBLIC\n"
        elif self.path.startswith(cfg["allowed"]):
            status, body = 207, cfg["body"].encode()
        elif self.path == cfg["error"]:
            status, body = 418, ("error-" + cfg["body"]).encode()
        else:
            status, body = 404, ("missing:" + self.path).encode()

        self.send_response(status)
        self.send_header("Content-Type", "application/x-trie-verifier")
        self.send_header("X-Backend-Token", cfg["token"])
        self.send_header("X-Backend-Path", self.path)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

HTTPServer(("127.0.0.1", 9090), Handler).serve_forever()
'''
    with open("/tmp/dynamic_backend.py", "w") as f:
        f.write(backend_source)

    backend = subprocess.Popen(
        ["python3", "/tmp/dynamic_backend.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    proxy = subprocess.Popen(
        ["python3", "proxy.py"],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    time.sleep(2)
    assert backend.poll() is None, "backend server failed to start"
    assert proxy.poll() is None, "proxy server failed to start"

    maps_path = f"/proc/{proxy.pid}/maps"
    with open(maps_path, errors="replace") as f:
        maps = f.read()
    assert "/home/user/libtrie.so" in maps, "proxy process did not load /home/user/libtrie.so"

    yield {"proxy": proxy, "backend": backend}

    for process in (proxy, backend):
        if process.poll() is None:
            process.terminate()
    for process in (proxy, backend):
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()

    with open("/home/user/blocked.txt", "wb") as f:
        f.write(old_blocked)


def fetch_full(path):
    url = f"http://127.0.0.1:8080{path}"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as response:
            return response.status, response.headers, response.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.headers, e.read().decode("utf-8")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to proxy: {e}")


def fetch_url(path):
    status, _headers, body = fetch_full(path)
    return status, body


def test_proxy_allowed_paths(servers):
    status, body = fetch_url("/index.html")
    assert status == 200, f"Expected status 200 for /index.html, got {status}"
    assert "OK" in body, "Expected 'OK' in response body for /index.html"

    status, body = fetch_url("/public.txt")
    assert status == 200, f"Expected status 200 for /public.txt, got {status}"
    assert "PUBLIC" in body, "Expected 'PUBLIC' in response body for /public.txt"

    status, body = fetch_url("/api/v1/public")
    assert status == 404, f"Expected status 404 for missing file /api/v1/public, got {status}"


def test_proxy_blocked_paths(servers):
    blocked_paths = [
        "/admin",
        "/admin.html",
        "/private/data",
        "/api/v1/secret/keys",
    ]

    for path in blocked_paths:
        status, body = fetch_url(path)
        assert status == 403, f"Expected status 403 for blocked path {path}, got {status}"
        assert "Blocked by Trie" in body, f"Expected 'Blocked by Trie' in response body for {path}"


def test_proxy_randomized_prefixes_and_ffi(servers):
    requested = []
    for prefix in RANDOM_PREFIXES:
        for path in (prefix, prefix + "/child-" + secrets.token_hex(5)):
            status, _headers, body = fetch_full(path)
            requested.append(path)
            assert status == 403, f"random blocked path {path} returned {status}"
            assert body == "Blocked by Trie", f"blocked response body was not exact for {path}"

    status, headers, _body = fetch_full(RANDOM_NEAR_MISS)
    requested.append(RANDOM_NEAR_MISS)
    assert status == 404, "a non-prefix near miss was incorrectly blocked"
    assert headers.get("X-Backend-Token") == BACKEND_TOKEN, "near-miss request was not forwarded to backend"

    with open(FFI_LOG) as f:
        lines = f.read().splitlines()
    assert "C" in lines, "proxy did not call trie_create through the shared library"
    for prefix in ORIGINAL_BLOCKED + RANDOM_PREFIXES:
        assert f"I {prefix}" in lines, f"proxy did not insert blocked prefix {prefix} through trie_insert"
    for path in requested:
        assert any(line.startswith(f"K {path} ") for line in lines), f"proxy did not call trie_check for {path}"


def test_proxy_preserves_arbitrary_backend_response(servers):
    query_path = RANDOM_ALLOWED + "/segment?alpha=" + secrets.token_hex(5) + "&beta=two"
    status, headers, body = fetch_full(query_path)
    assert status == 207, f"backend status was not preserved: got {status}"
    assert body == BACKEND_BODY, "backend body was not preserved"
    assert headers.get("Content-Type") == "application/x-trie-verifier", "backend Content-Type was not preserved"
    assert headers.get("X-Backend-Token") == BACKEND_TOKEN, "arbitrary backend header was not preserved"
    assert headers.get("X-Backend-Path") == query_path, "proxy did not preserve the exact backend path and query"
    assert headers.get("Content-Length") == str(len(BACKEND_BODY.encode())), "backend Content-Length was not preserved"

    status, headers, body = fetch_full(RANDOM_ERROR)
    assert status == 418, f"backend error status was not preserved: got {status}"
    assert body == "error-" + BACKEND_BODY, "backend error body was not preserved"
    assert headers.get("X-Backend-Token") == BACKEND_TOKEN, "headers on backend error response were not preserved"

    with open(FFI_LOG) as f:
        lines = f.read().splitlines()
    assert any(line.startswith(f"K {RANDOM_ALLOWED}") for line in lines), "allowed request was not checked with trie_check"
    assert any(line.startswith(f"K {RANDOM_ERROR} ") for line in lines), "backend error request was not checked with trie_check"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
