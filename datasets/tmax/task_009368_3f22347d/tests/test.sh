#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import random
import re
import subprocess
import tempfile
import urllib.request

WORKSPACE = "/home/user/workspace"
LIB_PATH = WORKSPACE + "/libmergediff.so"
SRC_PATH = WORKSPACE + "/src/mergediff.c"
SERVER_PATH = WORKSPACE + "/server.py"
NGINX_PATH = WORKSPACE + "/nginx.conf"


def expected_diff(a, b):
    sa = set(a)
    sb = set(b)
    return {
        "only_a": sorted(sa - sb),
        "only_b": sorted(sb - sa),
        "both": sorted(sa & sb),
    }


def call_compute_diff(library_path, a, b):
    lib = ctypes.CDLL(library_path)
    fn = lib.compute_diff
    int_p = ctypes.POINTER(ctypes.c_int)
    fn.argtypes = [
        int_p, ctypes.c_int, int_p, ctypes.c_int,
        int_p, int_p, int_p, int_p, int_p, int_p,
    ]
    fn.restype = None

    a_buf = (ctypes.c_int * max(1, len(a)))(*a)
    b_buf = (ctypes.c_int * max(1, len(b)))(*b)
    only_a = (ctypes.c_int * max(1, len(a)))()
    only_b = (ctypes.c_int * max(1, len(b)))()
    both = (ctypes.c_int * max(1, min(len(a), len(b))))()
    len_only_a = ctypes.c_int(-1)
    len_only_b = ctypes.c_int(-1)
    len_both = ctypes.c_int(-1)

    fn(
        a_buf, len(a), b_buf, len(b),
        only_a, ctypes.byref(len_only_a),
        only_b, ctypes.byref(len_only_b),
        both, ctypes.byref(len_both),
    )

    assert 0 <= len_only_a.value <= len(a)
    assert 0 <= len_only_b.value <= len(b)
    assert 0 <= len_both.value <= min(len(a), len(b))
    return {
        "only_a": list(only_a[:len_only_a.value]),
        "only_b": list(only_b[:len_only_b.value]),
        "both": list(both[:len_both.value]),
    }


def post_diff(port, a, b):
    data = json.dumps({"a": a, "b": b}).encode("utf-8")
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/diff",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.status == 200, f"Expected HTTP status 200, got {response.status}"
        return json.loads(response.read().decode("utf-8"))


def listener_inodes(port):
    result = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_pids(port):
    inodes = listener_inodes(port)
    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return found


def proc_cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def test_files_exist():
    expected_files = [
        SRC_PATH,
        LIB_PATH,
        SERVER_PATH,
        NGINX_PATH,
        WORKSPACE + "/status.log",
    ]
    for filepath in expected_files:
        assert os.path.isfile(filepath), f"Expected file {filepath} is missing."


def test_status_ready():
    with open(WORKSPACE + "/status.log", "r") as f:
        content = f.read()
    assert "READY" in content, "status.log does not contain 'READY'."


def test_c_source_builds_and_compute_diff_works_directly():
    cases = [
        ([], []),
        ([], [-4, 0, 9]),
        ([-9, -2, 7], []),
        ([1], [1]),
        ([-10, -3, 0, 8], [-9, -3, 8, 11]),
        ([-2147483648, -1, 2147483647], [-2147483648, 0, 2147483647]),
        ([1, 2, 4, 8, 16], [2, 4, 10, 20]),
    ]
    rng = random.Random(913704)
    universe = list(range(-150, 151))
    for _ in range(30):
        a = sorted(rng.sample(universe, rng.randrange(0, 45)))
        b = sorted(rng.sample(universe, rng.randrange(0, 45)))
        cases.append((a, b))

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "libmergediff.so")
        subprocess.check_call([
            "gcc", "-shared", "-fPIC", "-DMINIMAL_BUILD", "-O2",
            SRC_PATH, "-o", rebuilt,
        ])
        for library in (LIB_PATH, rebuilt):
            for a, b in cases:
                actual = call_compute_diff(library, a, b)
                assert actual == expected_diff(a, b), (
                    f"compute_diff from {library} failed for a={a}, b={b}: {actual}"
                )


def test_server_uses_ctypes_library_and_compute_diff():
    with open(SERVER_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SERVER_PATH)

    ctypes_names = {"ctypes"}
    cdll_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "ctypes":
                    ctypes_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == "ctypes":
            for alias in node.names:
                if alias.name == "CDLL":
                    cdll_names.add(alias.asname or alias.name)

    loads_required_library = False
    references_compute_diff = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and node.attr == "compute_diff":
            references_compute_diff = True
        if isinstance(node, ast.Call):
            is_cdll = (
                isinstance(node.func, ast.Name) and node.func.id in cdll_names
            ) or (
                isinstance(node.func, ast.Attribute)
                and node.func.attr == "CDLL"
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in ctypes_names
            )
            if is_cdll and node.args:
                arg = node.args[0]
                if isinstance(arg, ast.Constant) and arg.value == LIB_PATH:
                    loads_required_library = True

    assert loads_required_library, "server.py must load libmergediff.so using ctypes.CDLL"
    assert references_compute_diff, "server.py must obtain and use the compute_diff symbol"

    pids = listener_pids(5000)
    assert pids, "No process is listening on 127.0.0.1:5000"
    valid = False
    for pid in pids:
        cmdline = proc_cmdline(pid)
        try:
            with open(f"/proc/{pid}/maps", "r", encoding="utf-8", errors="replace") as f:
                maps = f.read()
        except OSError:
            maps = ""
        if "server.py" in cmdline and LIB_PATH in maps:
            valid = True
            break
    assert valid, "The Python server listening on port 5000 has not loaded libmergediff.so"


def test_nginx_is_the_reverse_proxy_on_8080():
    with open(NGINX_PATH, "r", encoding="utf-8") as f:
        config = f.read()
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\b", config), "nginx.conf does not listen on 127.0.0.1:8080"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;", config), "nginx.conf does not proxy to port 5000"

    pids = listener_pids(8080)
    assert pids, "No process is listening on port 8080"
    nginx_pids = [pid for pid in pids if "nginx" in proc_cmdline(pid).lower()]
    assert nginx_pids, "Port 8080 is not owned by an Nginx process"
    assert any(NGINX_PATH in proc_cmdline(pid) for pid in nginx_pids), (
        "The Nginx process on port 8080 was not started with the required nginx.conf"
    )


def test_api_endpoint_via_nginx():
    cases = [
        ([1, 2, 4, 8, 16], [2, 4, 10, 20]),
        ([], []),
        ([], [-7, 2, 99]),
        ([-20, -4, 0, 3], []),
        ([-8, -2, 5, 11], [-9, -2, 0, 11, 15]),
        ([42], [42]),
        ([-2147483648, 2147483647], [-2147483648, -1, 2147483647]),
    ]
    rng = random.Random(480821)
    universe = list(range(-300, 301))
    for _ in range(18):
        a = sorted(rng.sample(universe, rng.randrange(0, 55)))
        b = sorted(rng.sample(universe, rng.randrange(0, 55)))
        cases.append((a, b))

    for a, b in cases:
        try:
            actual = post_diff(8080, a, b)
        except Exception as e:
            assert False, f"Failed to communicate with the API via Nginx on port 8080: {e}"
        expected = expected_diff(a, b)
        assert actual.get("only_a") == expected["only_a"], f"Incorrect only_a for a={a}, b={b}"
        assert actual.get("only_b") == expected["only_b"], f"Incorrect only_b for a={a}, b={b}"
        assert actual.get("both") == expected["both"], f"Incorrect both for a={a}, b={b}"


def test_minimal_build():
    try:
        output = subprocess.check_output(
            ["nm", "-u", LIB_PATH], stderr=subprocess.STDOUT
        ).decode("utf-8")
        forbidden_symbols = ["printf", "malloc", "free", "puts"]
        for sym in forbidden_symbols:
            assert sym not in output, (
                f"Shared library contains forbidden symbol '{sym}' despite MINIMAL_BUILD requirement."
            )
    except FileNotFoundError:
        pass
    except subprocess.CalledProcessError:
        assert False, "Failed to run nm on libmergediff.so. Is it a valid shared library?"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
