#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import time

import pytest

LIBDIR = "/app/libmathops-1.2.0"
PRDIR = "/app/pr-104"
SCRIPT = "/home/user/server.sh"
PORT = 9090


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, **kwargs)


def strip_c_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port == PORT:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    if not inodes:
        return pids
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_server():
    for sig in (signal.SIGTERM, signal.SIGKILL):
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, sig)
            except ProcessLookupError:
                pass
        time.sleep(0.4)
    assert not listener_pids(), "Could not stop the existing listener on port 9090"


def wait_for_server(proc, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", PORT), timeout=0.2):
                return
        except OSError:
            if proc.poll() is not None:
                raise AssertionError(
                    f"server.sh exited before listening (status {proc.returncode})"
                )
            time.sleep(0.1)
    raise AssertionError("server.sh did not begin listening on 127.0.0.1:9090")


def start_server():
    stop_server()
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    proc = subprocess.Popen(
        ["bash", SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=env
    )
    wait_for_server(proc)
    return proc


def request(payload):
    wire = json.dumps(payload, separators=(",", ":")) + "\n"
    with socket.create_connection(("127.0.0.1", PORT), timeout=5) as sock:
        sock.sendall(wire.encode())
        data = b""
        while b"\n" not in data:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
    assert data, "Server closed the connection without responding"
    first, sep, remainder = data.partition(b"\n")
    assert sep == b"\n", "Server response was not newline terminated"
    assert not remainder.strip(), f"Server returned extra output: {remainder!r}"
    try:
        obj = json.loads(first.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        pytest.fail(f"Server returned invalid JSON: {data!r}: {exc}")
    assert isinstance(obj, dict), f"Response is not a JSON object: {obj!r}"
    assert set(obj) == {"result"}, f"Response must contain exactly result: {obj!r}"
    assert isinstance(obj["result"], int) and not isinstance(obj["result"], bool)
    return obj["result"]


def fibmod(n, mod):
    a, b = 0, 1
    for _ in range(n):
        a, b = b % mod, (a + b) % mod
    return a


def test_libmathops_makefile_fixed():
    """Keep the original source assertion and prove the flag is used by make."""
    makefile = os.path.join(LIBDIR, "Makefile")
    with open(makefile) as f:
        content = f.read()
    assert "-fPIC" in content, "Makefile in /app/libmathops-1.2.0 is still missing -fPIC"

    source = os.path.join(LIBDIR, "mathops.c")
    with open(source) as f:
        original = f.read()
    probe = "\nint verifier_pic_global;\nint verifier_pic_probe(void) { return verifier_pic_global; }\n"
    try:
        with open(source, "w") as f:
            f.write(original + probe)
        run(["make", "clean"], cwd=LIBDIR)
        built = run(["make"], cwd=LIBDIR)
        assert built.returncode == 0, f"Vendored library does not build as PIC:\n{built.stdout}"
        assert "-fPIC" in built.stdout, f"The actual compilation did not use -fPIC:\n{built.stdout}"
        elf = run(["readelf", "-h", os.path.join(LIBDIR, "libmathops.so")])
        assert elf.returncode == 0 and "DYN (Shared object file)" in elf.stdout
    finally:
        with open(source, "w") as f:
            f.write(original)
        run(["make", "clean"], cwd=LIBDIR)
    rebuilt = run(["make"], cwd=LIBDIR)
    assert rebuilt.returncode == 0, f"Final libmathops build failed:\n{rebuilt.stdout}"


def test_fibfast_memory_leak_fixed():
    """Keep the original assertion, reject the comment loophole, and exercise it repeatedly."""
    source = os.path.join(PRDIR, "fibfast.c")
    with open(source) as f:
        content = f.read()
    assert "free(" in content, "fibfast.c is missing a call to free() to fix the memory leak"
    code = strip_c_comments(content)
    assignment = re.search(r"\b(?:char\s*\*|char\s+\*)\s*res\s*=\s*compute_fib\s*\([^;]*\)\s*;", code)
    assert assignment, "Could not find the result returned by compute_fib"
    after = code[assignment.end():]
    free_call = re.search(r"\bfree\s*\(\s*res\s*\)\s*;", after)
    ret = re.search(r"\breturn\b", after)
    assert free_call and (not ret or free_call.start() < ret.start()), \
        "The compute_fib result is not actually freed on the primary execution path"

    run(["make", "clean"], cwd=PRDIR)
    built = run(["make"], cwd=PRDIR)
    assert built.returncode == 0, f"fibfast.so failed to build:\n{built.stdout}"
    so = os.path.join(PRDIR, "fibfast.so")
    assert os.path.isfile(so), "make did not produce fibfast.so"
    elf = run(["readelf", "-h", so])
    assert elf.returncode == 0 and "DYN (Shared object file)" in elf.stdout

    # A missing free leaks roughly 20+ MiB in this single long-lived Bash process.
    stress = r'''
enable -f /app/pr-104/fibfast.so fibfast || exit 20
for ((i=0;i<5000;i++)); do fibfast 1 1000000007 >/dev/null || exit 21; done
rss_before=0
while read -r key value rest; do [[ $key == VmRSS: ]] && rss_before=$value; done < /proc/$$/status
for ((i=0;i<300000;i++)); do fibfast 1 1000000007 >/dev/null || exit 22; done
rss_after=0
while read -r key value rest; do [[ $key == VmRSS: ]] && rss_after=$value; done < /proc/$$/status
printf '%s %s\n' "$rss_before" "$rss_after"
'''
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = LIBDIR
    measured = run(["bash", "-c", stress], env=env, timeout=45)
    assert measured.returncode == 0, f"Builtin stress test failed:\n{measured.stdout}"
    before, after = map(int, measured.stdout.strip().split()[-2:])
    assert after - before < 12288, \
        f"Builtin memory grew by {after-before} KiB; compute_fib results appear to leak"


def test_builtin_computes_dynamic_inputs():
    rng = random.SystemRandom()
    cases = [(rng.randrange(0, 500), rng.randrange(2, 2_000_000_000)) for _ in range(16)]
    commands = ["enable -f /app/pr-104/fibfast.so fibfast || exit 30"]
    commands += [f"fibfast {n} {m} || exit 31" for n, m in cases]
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = LIBDIR
    result = run(["bash", "-c", "; ".join(commands)], env=env)
    assert result.returncode == 0, f"Could not load and execute fibfast.so:\n{result.stdout}"
    values = [int(x) for x in result.stdout.splitlines()]
    assert values == [fibmod(n, m) for n, m in cases]


def test_server_script_exists():
    """Original existence assertion plus required, uncommented setup commands."""
    assert os.path.isfile(SCRIPT), "/home/user/server.sh does not exist"
    with open(SCRIPT) as f:
        text = f.read()
    shell_code = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    assert re.search(r"\benable\s+-f\s+/app/pr-104/fibfast\.so\s+fibfast\b", shell_code), \
        "server.sh does not load the requested fibfast builtin"
    assert "LD_LIBRARY_PATH" in shell_code and "/app/libmathops-1.2.0" in shell_code
    assert "9090" in shell_code, "server.sh does not configure port 9090"


def test_server_response():
    global server_proc
    server_proc = start_server()
    assert request({"n": 10, "mod": 100}) == 55


def test_server_burst_requests():
    for _ in range(100):
        assert request({"n": 100, "mod": 1000000007}) == 687995182


def test_server_dynamic_requests():
    rng = random.SystemRandom()
    cases = [(rng.randrange(0, 1000), rng.randrange(2, 2_000_000_000)) for _ in range(24)]
    rng.shuffle(cases)
    for n, mod in cases:
        assert request({"mod": mod, "n": n}) == fibmod(n, mod)


def test_server_really_uses_compiled_builtin_and_library():
    """Relaunch against a temporary library whose answers cannot be ordinary Fibonacci."""
    global server_proc
    stop_server()
    real_so = os.path.join(LIBDIR, "libmathops.so")
    backup = real_so + ".verifier-backup"
    shutil.copy2(real_so, backup)
    probe_c = os.path.join(LIBDIR, ".verifier_probe.c")
    probe_source = r'''
#include <stdio.h>
#include <stdlib.h>
char *compute_fib(long long n, long long mod) {
    unsigned long long v = ((unsigned long long)n * 1000003ULL +
                            (unsigned long long)mod * 97ULL + 424242ULL) % 2000000000ULL;
    char *p = malloc(64);
    if (!p) return NULL;
    snprintf(p, 64, "%llu", v);
    return p;
}
'''
    try:
        with open(probe_c, "w") as f:
            f.write(probe_source)
        compiled = run(["gcc", "-fPIC", "-shared", "-o", real_so, probe_c])
        assert compiled.returncode == 0, compiled.stdout
        server_proc = start_server()
        rng = random.SystemRandom()
        for _ in range(8):
            n = rng.randrange(3, 100000)
            mod = rng.randrange(101, 2_000_000_000)
            expected = (n * 1000003 + mod * 97 + 424242) % 2000000000
            assert request({"n": n, "mod": mod}) == expected, \
                "server.sh is not serving requests through fibfast.so and libmathops.so"
    finally:
        stop_server()
        if os.path.exists(backup):
            os.replace(backup, real_so)
        try:
            os.unlink(probe_c)
        except FileNotFoundError:
            pass
        # Leave the required normal server running after verification.
        server_proc = start_server()
        assert request({"n": 23, "mod": 1000003}) == fibmod(23, 1000003)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
