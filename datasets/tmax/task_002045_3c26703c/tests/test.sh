#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import glob
import http.client
import os
import re
import signal
import socket
import subprocess
import tarfile
import time
import uuid


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_processes(port):
    inodes = listening_inodes(port)
    found = {}
    if not inodes:
        return found
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(procdir + "/fd"):
                try:
                    target = os.readlink(procdir + "/fd/" + fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    try:
                        found[pid] = os.path.realpath(procdir + "/exe")
                    except OSError:
                        found[pid] = ""
                    break
        except OSError:
            pass
    return found


def stop_port(port):
    for pid in listener_processes(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_inodes(port):
        time.sleep(0.05)


def request(path, token=None):
    headers = {}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=3)
    try:
        conn.request("GET", path, headers=headers)
        response = conn.getresponse()
        body = response.read()
        return response.status, response.version, dict(response.getheaders()), body
    finally:
        conn.close()


def expected_state():
    with open("/app/legacy.log", encoding="utf-8") as f:
        log = f.read()
    records = re.findall(
        r"\[RECORD START\]\s*ID:\s*[^\n]+\s*Key:\s*([^\n]+)\s*Value:\s*([^\n]+)\s*\[RECORD END\]",
        log,
    )
    assert records, "No records could be derived from legacy.log"
    base = b"".join((key.strip() + "=" + value.strip() + "\n").encode() for key, value in records)

    patch_files = {}
    valid_archives = []
    invalid_archives = []
    for archive in sorted(glob.glob("/app/updates/*.tar.gz")):
        try:
            with tarfile.open(archive, "r:gz") as tf:
                members = tf.getmembers()
                for member in members:
                    if member.name.startswith("/") or ".." in member.name.split("/"):
                        raise AssertionError("Unsafe member in fixture archive")
                valid_archives.append(archive)
                for member in members:
                    if member.isfile():
                        extracted = tf.extractfile(member)
                        assert extracted is not None
                        rel = member.name
                        if rel.endswith(".conf.tmp"):
                            rel = rel[:-4]
                        patch_files[rel] = extracted.read()
        except (tarfile.TarError, EOFError, OSError):
            invalid_archives.append(archive)

    assert valid_archives, "Fixture has no valid update archive"
    assert invalid_archives, "Fixture has no corrupt update archive"
    conf_data = [patch_files[p] for p in sorted(patch_files) if p.endswith(".conf")]
    final = base + b"".join(conf_data)
    return base, patch_files, final


def test_complete_workflow_and_c_server():
    base_expected, patches_expected, final_expected = expected_state()

    base_path = "/home/user/configs/base.conf"
    final_path = "/home/user/configs/final.conf"
    patches_root = "/home/user/configs/patches"
    source_path = "/home/user/server.c"
    submitted_binary = "/home/user/server"

    # Preserve the original state assertions, while requiring exact derived output.
    assert os.path.isfile(base_path), f"Missing base configuration file at {base_path}"
    with open(base_path, "rb") as f:
        base_actual = f.read()
    assert b"max_connections=500" in base_actual
    assert b"timeout=30s" in base_actual
    assert base_actual == base_expected, "base.conf is not the exact parse of legacy.log"

    assert os.path.isfile(final_path), f"Missing final configuration file at {final_path}"
    with open(final_path, "rb") as f:
        final_actual = f.read()
    assert b"max_connections=500" in final_actual
    assert b"timeout=30s" in final_actual
    assert b"db_host=localhost" in final_actual
    assert final_actual == final_expected, "final.conf is not the derived base plus valid patches"

    renamed = "/home/user/configs/patches/patch1/db/database.conf"
    temporary = renamed + ".tmp"
    assert os.path.isfile(renamed), f"Renamed patch file not found at {renamed}"
    assert not os.path.exists(temporary), "Temporary patch file was not renamed"

    actual_patch_files = {}
    for root, dirs, files in os.walk(patches_root):
        for name in files:
            path = os.path.join(root, name)
            assert not name.endswith(".conf.tmp"), f"Unrenamed patch file remains: {path}"
            assert os.path.isfile(path) and not os.path.islink(path)
            rel = os.path.relpath(path, patches_root)
            with open(path, "rb") as f:
                actual_patch_files[rel] = f.read()
    assert actual_patch_files == patches_expected, "Patches do not exactly match the valid archives"

    # Require the requested source and a real executable ELF artifact.
    assert os.path.isfile(source_path), "Missing /home/user/server.c"
    assert os.path.isfile(submitted_binary), "Missing /home/user/server"
    assert os.access(submitted_binary, os.X_OK), "/home/user/server is not executable"
    with open(submitted_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/server is not an ELF executable"

    verified_binary = "/tmp/verified_config_server"
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", source_path, "-o", verified_binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert build.returncode == 0, "server.c does not compile:\n" + build.stderr

    # Interpose mmap and record only mappings of the required final.conf path.
    interposer_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

typedef void *(*mmap_fn)(void *, size_t, int, int, int, off_t);
void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off) {
    static mmap_fn real_mmap;
    if (!real_mmap) real_mmap = (mmap_fn)dlsym(RTLD_NEXT, "mmap");
    void *result = real_mmap(addr, len, prot, flags, fd, off);
    if (fd >= 0) {
        char linkpath[64], target[512];
        int n;
        n = snprintf(linkpath, sizeof(linkpath), "/proc/self/fd/%d", fd);
        if (n > 0) {
            ssize_t got = readlink(linkpath, target, sizeof(target) - 1);
            if (got > 0) {
                target[got] = '\0';
                if (!strcmp(target, "/home/user/configs/final.conf")) {
                    int out = (int)syscall(SYS_openat, AT_FDCWD, "/tmp/final_mmap.log", O_WRONLY|O_CREAT|O_APPEND, 0600);
                    if (out >= 0) {
                        syscall(SYS_write, out, "mmap-final\n", 11);
                        syscall(SYS_close, out);
                    }
                }
            }
        }
    }
    return result;
}
'''
    # snprintf declaration
    interposer_source = interposer_source.replace("#include <string.h>", "#include <string.h>\n#include <stdio.h>")
    with open("/tmp/mmap_check.c", "w") as f:
        f.write(interposer_source)
    hook_build = subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/mmap_check.c", "-o", "/tmp/mmap_check.so", "-ldl"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert hook_build.returncode == 0, hook_build.stderr

    # Add an unpredictable value so a fixed-response server cannot satisfy the body check.
    nonce = "verifier_nonce=" + uuid.uuid4().hex
    dynamic_final = final_expected + nonce.encode() + b"\n"
    with open(final_path, "wb") as f:
        f.write(dynamic_final)

    stop_port(8080)
    try:
        os.unlink("/tmp/final_mmap.log")
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["LD_PRELOAD"] = "/tmp/mmap_check.so"
    server = subprocess.Popen(
        [verified_binary], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        deadline = time.time() + 6
        while time.time() < deadline:
            if server.poll() is not None:
                raise AssertionError("Compiled server.c exited before serving requests")
            try:
                request("/api/config")
                break
            except (OSError, http.client.HTTPException):
                time.sleep(0.1)
        else:
            raise AssertionError("Compiled server.c did not listen on port 8080")

        listeners = listener_processes(8080)
        assert listeners, "No process is listening on port 8080"
        assert all(os.path.samefile(exe, verified_binary) for exe in listeners.values()), \
            f"Port 8080 is not served by the compiled C artifact: {listeners}"

        token = "echo-bravo-niner-tango"
        status, version, headers, body = request("/api/config", token)
        assert status == 200, f"Expected status code 200, got {status}"
        assert version == 11, "Server did not return an HTTP/1.1 response"
        content_type = next((v for k, v in headers.items() if k.lower() == "content-type"), "")
        assert "text/plain" in content_type, "Expected Content-Type: text/plain"
        assert b"max_connections=500" in body
        assert b"timeout=30s" in body
        assert b"db_host=localhost" in body
        assert body == dynamic_final, "Authenticated response is not the exact current final.conf"

        assert request("/api/config", "wrong-token-123")[0] == 401
        assert request("/api/config")[0] == 401
        assert request("/api/config", token + "-extra")[0] == 401
        assert request("/not-the-endpoint", token)[0] != 200

        deadline = time.time() + 2
        while time.time() < deadline and not os.path.exists("/tmp/final_mmap.log"):
            time.sleep(0.05)
        assert os.path.exists("/tmp/final_mmap.log"), \
            "The compiled server did not mmap /home/user/configs/final.conf"
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=2)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        stop_port(8080)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
