#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import random
import shutil
import string
import subprocess
import tempfile

API_BASE = "https://secure.backend.local"
MIN_VERSION = "2.1.0"
CLI = "/home/user/router_cli.py"
SOURCE = "/home/user/librouter.c"
LIBRARY = "/home/user/librouter.so"


def expected(path, version):
    parts1 = [int(x) for x in version.split('.')]
    parts2 = [int(x) for x in MIN_VERSION.split('.')]
    if parts1 < parts2:
        return "ERROR: Version too old"
    if "?" in path:
        base_path, query = path.split("?", 1)
        param_str = ", ".join(query.split("&"))
    else:
        base_path = path
        param_str = "none"
    return f"ROUTED: {API_BASE}{base_path} PARAMS: {param_str}"


def generate_arg1():
    v = random.choice(['1', '2', '3'])
    path_len = random.randint(5, 10)
    path_str = ''.join(random.choices(string.ascii_lowercase, k=path_len))
    res = f"/api/v{v}/{path_str}"
    if random.random() < 0.5:
        return res
    res += "?"
    params = []
    for _ in range(1 + random.randint(0, 3)):
        key = ''.join(random.choices(string.ascii_lowercase, k=3))
        val = ''.join(random.choices(string.digits, k=random.randint(1, 4)))
        params.append(f"{key}={val}")
    return res + "&".join(params)


def generate_arg2():
    return f"{random.choice(['1', '2', '3'])}.{random.choice(string.digits)}.{random.choice(string.digits)}"


def run_cli(path, version):
    return subprocess.run(
        ["python3", CLI, path, version], capture_output=True, text=True, timeout=5
    )


def test_required_artifacts_and_interface():
    assert os.path.isfile(CLI), "Agent script /home/user/router_cli.py not found"
    assert os.path.isfile(SOURCE), "C source /home/user/librouter.c not found"
    assert os.path.isfile(LIBRARY), "Shared library /home/user/librouter.so not found"

    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "librouter.so is not an ELF shared library"

    inspected = subprocess.run(["readelf", "-h", LIBRARY], capture_output=True, text=True)
    assert inspected.returncode == 0, inspected.stderr
    assert "DYN (Shared object file)" in inspected.stdout, "librouter.so is not a shared object"

    lib = ctypes.CDLL(LIBRARY)
    assert getattr(lib, "process_route", None) is not None, "process_route is not exported"

    with open(CLI, "r", encoding="utf-8") as f:
        wrapper_source = f.read()
    assert "ctypes" in wrapper_source, "router_cli.py does not use ctypes"
    assert "process_route" in wrapper_source, "router_cli.py does not call process_route"


def test_c_function_and_cli_fuzz_equivalence():
    lib = ctypes.CDLL(LIBRARY)
    process = lib.process_route
    process.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    process.restype = ctypes.c_void_p
    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]
    libc.free.restype = None

    random.seed(42)
    cases = [
        ("/", "2.1.0"),
        ("/x", "2.0.9"),
        ("/x?", "2.1.0"),
        ("/x?a=1&&b=2", "3.0.0"),
        ("/x?first=1?second=2", "2.1.1"),
    ]
    cases.extend((generate_arg1(), generate_arg2()) for _ in range(200))

    for i, (path, version) in enumerate(cases):
        want = expected(path, version)

        ptr = process(path.encode(), version.encode())
        assert ptr, f"process_route returned NULL on iteration {i}"
        try:
            c_out = ctypes.string_at(ptr).decode()
        finally:
            libc.free(ptr)
        assert c_out == want, (
            f"C mismatch on iteration {i}: {path} {version}\n"
            f"Expected: {want}\nActual: {c_out}"
        )

        agent_res = run_cli(path, version)
        assert agent_res.returncode == 0, (
            f"Agent script failed on input: {path} {version}\nStderr: {agent_res.stderr}"
        )
        assert agent_res.stdout.strip() == want, (
            f"CLI mismatch on iteration {i}: {path} {version}\n"
            f"Expected: {want}\nActual: {agent_res.stdout.strip()}"
        )


def test_cli_really_calls_the_shared_library():
    shim_source = r'''
#include <stdlib.h>
#include <string.h>
char* process_route(const char* path, const char* version) {
    (void)path;
    (void)version;
    const char *value = "CTYPES_RUNTIME_SENTINEL_7f29";
    char *result = malloc(strlen(value) + 1);
    if (result) strcpy(result, value);
    return result;
}
void free_route(char *value) { free(value); }
'''
    with tempfile.TemporaryDirectory() as td:
        shim_c = os.path.join(td, "shim.c")
        shim_so = os.path.join(td, "shim.so")
        backup = os.path.join(td, "original.so")
        with open(shim_c, "w", encoding="utf-8") as f:
            f.write(shim_source)
        built = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", "-o", shim_so, shim_c],
            capture_output=True, text=True
        )
        assert built.returncode == 0, built.stderr
        shutil.copy2(LIBRARY, backup)
        try:
            os.replace(shim_so, LIBRARY)
            result = run_cli("/must/use/library?x=1", "9.9.9")
        finally:
            shutil.copy2(backup, LIBRARY)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "CTYPES_RUNTIME_SENTINEL_7f29", (
        "router_cli.py did not return the value produced by process_route in librouter.so"
    )


def test_cli_requires_exactly_two_arguments():
    for args in ([], ["/only-one"], ["/x", "2.1.0", "extra"]):
        result = subprocess.run(["python3", CLI] + args, capture_output=True, text=True, timeout=5)
        assert result.returncode != 0, f"CLI accepted invalid argument count: {args}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
