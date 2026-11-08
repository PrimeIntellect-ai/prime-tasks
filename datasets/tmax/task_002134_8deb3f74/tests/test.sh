#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import pathlib
import shutil
import subprocess
import tempfile
import uuid

import pytest

WORKSPACE = pathlib.Path("/home/user/workspace")
LIB_PATH = WORKSPACE / "libgraph.so"
SCRIPT_PATH = WORKSPACE / "resolve.py"
DEPS_PATH = WORKSPACE / "deps.txt"
OUTPUT_PATH = WORKSPACE / "build_order.txt"
C_PATH = WORKSPACE / "graph.c"


def deterministic_order(text):
    names = []
    index = {}
    indegree = []
    edges = []

    def node(name):
        if name not in index:
            index[name] = len(names)
            names.append(name)
            indegree.append(0)
            edges.append([])
        return index[name]

    for raw_line in text.splitlines():
        if ":" not in raw_line:
            continue
        target_name, dep_text = raw_line.split(":", 1)
        target = node(target_name)
        for dep_name in (part for part in dep_text.split(" ") if part):
            dep = node(dep_name)
            edges[dep].append(target)
            indegree[target] += 1

    queue = [i for i, degree in enumerate(indegree) if degree == 0]
    result = []
    head = 0
    while head < len(queue):
        current = queue[head]
        head += 1
        result.append(names[current])
        for target in edges[current]:
            indegree[target] -= 1
            if indegree[target] == 0:
                queue.append(target)
    return result


def run_resolver():
    return subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        cwd=str(WORKSPACE),
        text=True,
        capture_output=True,
        timeout=15,
    )


def read_output():
    assert OUTPUT_PATH.is_file(), f"Output file {OUTPUT_PATH} was not created."
    return [line.strip() for line in OUTPUT_PATH.read_text().splitlines() if line.strip()]


def call_library(dependency_file):
    lib = ctypes.CDLL(str(LIB_PATH))
    string_array = ctypes.POINTER(ctypes.c_char_p)
    lib.get_build_order.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
    lib.get_build_order.restype = string_array
    lib.free_build_order.argtypes = [string_array, ctypes.c_int]
    lib.free_build_order.restype = None

    count = ctypes.c_int(-1)
    order = lib.get_build_order(os.fsencode(dependency_file), ctypes.byref(count))
    assert bool(order), "get_build_order returned NULL for a readable dependency file"
    assert 0 <= count.value <= 100, f"get_build_order returned an invalid count: {count.value}"
    try:
        return [order[i].decode("utf-8") for i in range(count.value)]
    finally:
        lib.free_build_order(order, count.value)


def random_dependency_text():
    p = "n" + uuid.uuid4().hex
    return (
        f"{p}_app: {p}_util {p}_core\n"
        f"{p}_util: {p}_base\n"
        f"{p}_core: {p}_base {p}_plugin\n"
        f"{p}_plugin: {p}_base\n"
        f"{p}_base:\n"
        f"{p}_tool: {p}_util\n"
    )


def test_libgraph_so_exists():
    """Verify that the shared library libgraph.so was compiled and is loadable."""
    assert LIB_PATH.is_file(), f"Shared library {LIB_PATH} was not found. Did you compile graph.c?"
    ctypes.CDLL(str(LIB_PATH))


def test_resolve_py_exists_and_uses_ctypes():
    """Verify that resolve.py exists, declares the required API, and executes."""
    assert SCRIPT_PATH.is_file(), f"Python script {SCRIPT_PATH} was not found."
    content = SCRIPT_PATH.read_text()
    assert "ctypes" in content, "resolve.py does not appear to use the ctypes module."
    assert "get_build_order" in content, "resolve.py does not appear to call get_build_order."
    assert "free_build_order" in content, "resolve.py does not appear to call free_build_order."

    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    result = run_resolver()
    assert result.returncode == 0, f"resolve.py failed:\n{result.stdout}\n{result.stderr}"


def test_build_order_output():
    """Verify that build_order.txt contains the original deterministic sort."""
    expected_order = [
        "module_e",
        "module_d",
        "module_b",
        "module_c",
        "module_a",
        "module_f",
    ]
    assert read_output() == expected_order, (
        f"build_order.txt content is incorrect. Expected {expected_order}, got {read_output()}."
    )


def test_library_on_derived_input_and_free():
    """Load the submitted library, call both C functions, and check a fresh graph."""
    text = random_dependency_text()
    expected = deterministic_order(text)
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as dep_file:
        dep_file.write(text)
        dep_name = dep_file.name
    try:
        assert call_library(dep_name) == expected
    finally:
        os.unlink(dep_name)


def test_resolver_uses_current_dependency_data():
    """Ensure resolve.py obtains its result dynamically rather than using canned output."""
    original = DEPS_PATH.read_bytes()
    text = random_dependency_text()
    expected = deterministic_order(text)
    try:
        DEPS_PATH.write_text(text)
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
        result = run_resolver()
        assert result.returncode == 0, f"resolve.py failed:\n{result.stdout}\n{result.stderr}"
        assert read_output() == expected
    finally:
        DEPS_PATH.write_bytes(original)
        if OUTPUT_PATH.exists():
            OUTPUT_PATH.unlink()
        run_resolver()


def test_resolver_really_calls_ffi_and_free():
    """Use a probe shared library to verify get_build_order and free_build_order are called."""
    first = "probe_" + uuid.uuid4().hex
    second = "probe_" + uuid.uuid4().hex
    marker = pathlib.Path(tempfile.gettempdir()) / ("freed_" + uuid.uuid4().hex)

    with tempfile.TemporaryDirectory() as td:
        td_path = pathlib.Path(td)
        probe_c = td_path / "probe.c"
        probe_so = td_path / "libgraph.so"
        backup = td_path / "submitted_libgraph.so"
        probe_c.write_text(f'''\
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
char** get_build_order(const char* filepath, int* out_count) {{
    if (!filepath || strcmp(filepath, "/home/user/workspace/deps.txt") != 0) return NULL;
    char** result = malloc(2 * sizeof(char*));
    if (!result) return NULL;
    result[0] = strdup("{first}");
    result[1] = strdup("{second}");
    *out_count = 2;
    return result;
}}
void free_build_order(char** order, int count) {{
    FILE* f = fopen("{marker}", "w");
    if (f) {{ fputs("freed", f); fclose(f); }}
    if (!order) return;
    for (int i = 0; i < count; i++) free(order[i]);
    free(order);
}}
''')
        compiled = subprocess.run(
            ["gcc", "-shared", "-fPIC", str(probe_c), "-o", str(probe_so)],
            text=True,
            capture_output=True,
        )
        assert compiled.returncode == 0, compiled.stderr

        shutil.copy2(LIB_PATH, backup)
        try:
            shutil.copy2(probe_so, LIB_PATH)
            if OUTPUT_PATH.exists():
                OUTPUT_PATH.unlink()
            result = run_resolver()
            assert result.returncode == 0, f"resolve.py failed with probe library:\n{result.stderr}"
            assert read_output() == [first, second], "resolve.py did not use get_build_order's returned array"
            assert marker.is_file(), "resolve.py did not call free_build_order"
        finally:
            shutil.copy2(backup, LIB_PATH)
            if marker.exists():
                marker.unlink()
            if OUTPUT_PATH.exists():
                OUTPUT_PATH.unlink()
            run_resolver()


def test_graph_c_bugs_fixed():
    """Verify that graph.c no longer contains the specific memory bugs."""
    assert C_PATH.is_file(), f"Source file {C_PATH} is missing."
    content = C_PATH.read_text()
    assert "malloc(strlen(name));" not in content, (
        "Bug 1 (missing +1 for null terminator in malloc) is still present in graph.c."
    )
    assert "char* result[100];" not in content, (
        "Bug 2 (stack-allocated result array) is still present in graph.c."
    )


def test_graph_c_under_address_sanitizer():
    """Compile the submitted source with ASan and exercise allocation, return, and free paths."""
    text = random_dependency_text()
    with tempfile.TemporaryDirectory() as td:
        td_path = pathlib.Path(td)
        dep_file = td_path / "deps.txt"
        dep_file.write_text(text)
        asan_lib = td_path / "libgraph_asan.so"
        harness_c = td_path / "harness.c"
        harness = td_path / "harness"
        harness_c.write_text(r'''
#include <stdlib.h>
#include <string.h>
char** get_build_order(const char*, int*);
void free_build_order(char**, int);
int main(int argc, char** argv) {
    for (int a = 1; a < argc; ++a) {
        int count = -1;
        char** order = get_build_order(argv[a], &count);
        if (!order || count < 0 || count > 100) return 2;
        for (int i = 0; i < count; ++i) {
            if (!order[i]) return 3;
            volatile size_t length = strlen(order[i]);
            (void)length;
        }
        free_build_order(order, count);
    }
    return 0;
}
''')
        build_lib = subprocess.run(
            ["gcc", "-fsanitize=address", "-fno-omit-frame-pointer", "-g", "-fPIC", "-shared",
             str(C_PATH), "-o", str(asan_lib)],
            text=True,
            capture_output=True,
        )
        assert build_lib.returncode == 0, f"graph.c failed ASan compilation:\n{build_lib.stderr}"
        build_harness = subprocess.run(
            ["gcc", "-fsanitize=address", "-fno-omit-frame-pointer", str(harness_c),
             "-L", td, "-lgraph_asan", f"-Wl,-rpath,{td}", "-o", str(harness)],
            text=True,
            capture_output=True,
        )
        assert build_harness.returncode == 0, build_harness.stderr
        env = os.environ.copy()
        env["ASAN_OPTIONS"] = "detect_leaks=0:abort_on_error=1"
        checked = subprocess.run(
            [str(harness), str(DEPS_PATH), str(dep_file)],
            text=True,
            capture_output=True,
            env=env,
            timeout=15,
        )
        assert checked.returncode == 0, (
            "AddressSanitizer detected a memory-safety failure:\n"
            + checked.stdout + "\n" + checked.stderr
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
