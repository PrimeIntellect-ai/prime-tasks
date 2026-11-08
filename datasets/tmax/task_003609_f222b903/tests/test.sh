#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import importlib.machinery
import importlib.util
import json
import os
import re
import sys
import tempfile
import types

PROJECT = "/home/user/project"
OUTPUT = "/home/user/output.txt"


def test_process_py_fixed():
    path = "/home/user/project/process.py"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "iteritems()" not in content, "process.py still contains Python 2 'iteritems()'."
    assert not re.search(r'print\s+"', content), "process.py still contains Python 2 print statements."
    assert "items()" in content, "process.py should use 'items()' instead of 'iteritems()'."
    assert "print(" in content, "process.py should use Python 3 'print()' function."


def test_myext_c_fixed():
    path = "/home/user/project/myext.c"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original source assertion in addition to runtime ASan checks.
    assert re.search(r'malloc\s*\(\s*len\s*\+\s*1\s*\)', content) or \
           re.search(r'calloc\s*\(', content) or \
           re.search(r'malloc\s*\(\s*len\s*\+\s*sizeof', content) or \
           re.search(r'malloc\s*\(\s*len\s*\+\s*2\s*\)', content), \
           "myext.c does not appear to have the malloc(len) bug fixed. Expected something like malloc(len + 1)."


def test_native_extension_was_built_and_works():
    sys.path.insert(0, PROJECT)
    try:
        sys.modules.pop("myext", None)
        myext = importlib.import_module("myext")
        module_path = os.path.realpath(myext.__file__)
        assert module_path.startswith(os.path.realpath(PROJECT) + os.sep)
        assert any(module_path.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), \
            f"myext was not imported as a compiled extension: {module_path}"

        for value in ("", "a", "abcdef", "x" * 200000):
            assert myext.reverse_string(value) == value[::-1]
    finally:
        if sys.path and sys.path[0] == PROJECT:
            sys.path.pop(0)


def test_output_file():
    output_path = "/home/user/output.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} was not created."

    graph_path = "/home/user/project/graph.json"
    assert os.path.isfile(graph_path), f"Graph file {graph_path} is missing."

    with open(graph_path, "r") as f:
        graph = json.load(f)

    expected_strings = []
    for node, data in graph.items():
        val = data.get("val", "")
        reversed_val = val[::-1]
        expected_strings.append(reversed_val)

    expected_strings.sort()
    expected_output = "\n".join(expected_strings) + "\n"

    with open(output_path, "r") as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output.strip(), \
        f"Output in {output_path} does not match the expected sorted reversed strings."


def test_process_uses_extension_and_dependency_order_on_derived_input():
    graph = {
        "final": {"deps": ["middle", "side"], "val": "FINAL_VALUE"},
        "middle": {"deps": ["root"], "val": "MIDDLE_VALUE"},
        "side": {"deps": ["root"], "val": "SIDE_VALUE"},
        "root": {"deps": [], "val": "ROOT_VALUE"},
    }
    value_to_node = {data["val"]: node for node, data in graph.items()}
    calls = []
    fake_ext = types.ModuleType("myext")

    def reverse_string(value):
        calls.append(value)
        return "checked:" + value[::-1]

    fake_ext.reverse_string = reverse_string
    old_module = sys.modules.get("myext")
    old_cwd = os.getcwd()
    previous_output = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, "rb") as f:
            previous_output = f.read()

    try:
        sys.modules["myext"] = fake_ext
        spec = importlib.util.spec_from_file_location(
            "candidate_process_runtime_test", os.path.join(PROJECT, "process.py")
        )
        candidate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(candidate)

        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "graph.json"), "w") as f:
                json.dump(graph, f)
            os.chdir(tmp)
            candidate.main()

        assert len(calls) == len(graph), "process.py did not process every graph node exactly once"
        assert set(calls) == set(value_to_node), "process.py did not pass graph values to myext.reverse_string"
        call_nodes = [value_to_node[value] for value in calls]
        positions = {node: i for i, node in enumerate(call_nodes)}
        for node, data in graph.items():
            for dep in data["deps"]:
                assert positions[dep] < positions[node], f"Dependency {dep} was processed after {node}"

        expected = sorted("checked:" + data["val"][::-1] for data in graph.values())
        with open(OUTPUT, "r") as f:
            actual = f.read().splitlines()
        assert actual == expected, "process.py did not write the sorted extension results"
    finally:
        os.chdir(old_cwd)
        if old_module is None:
            sys.modules.pop("myext", None)
        else:
            sys.modules["myext"] = old_module
        if previous_output is None:
            try:
                os.remove(OUTPUT)
            except FileNotFoundError:
                pass
        else:
            with open(OUTPUT, "wb") as f:
                f.write(previous_output)
TEST_EOF

ok=1
cd /home/user/project || ok=0

if [ "$ok" -eq 1 ]; then
    rm -rf build
    rm -f myext*.so myext*.pyd
    CFLAGS="-fsanitize=address -fno-omit-frame-pointer" \
    LDFLAGS="-fsanitize=address" \
    python3 setup.py build_ext --inplace || ok=0
fi

ASAN_LIB="$(gcc -print-file-name=libasan.so 2>/dev/null || true)"
if [ "$ok" -eq 1 ] && { [ -z "$ASAN_LIB" ] || [ ! -f "$ASAN_LIB" ]; }; then
    ok=0
fi

if [ "$ok" -eq 1 ]; then
    rm -f /home/user/output.txt
    ASAN_OPTIONS="detect_leaks=0:halt_on_error=1" LD_PRELOAD="$ASAN_LIB" \
        python3 process.py || ok=0
fi

if [ "$ok" -eq 1 ]; then
    ASAN_OPTIONS="detect_leaks=0:halt_on_error=1" LD_PRELOAD="$ASAN_LIB" \
        python3 -m pytest /tmp/test_final_state.py -x --tb=short || ok=0
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
