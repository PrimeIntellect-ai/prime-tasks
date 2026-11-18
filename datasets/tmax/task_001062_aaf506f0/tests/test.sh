#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile
import pytest

BASE_DIR = "/home/user/release_prep"
SERVER_SECURE = os.path.join(BASE_DIR, "server_secure")
DEP_GRAPH = os.path.join(BASE_DIR, "dep_graph.txt")
EXPECTED_OBJECTS = ["server.o", "http_parser.o", "vendor/auth.o", "clean_stub.o"]


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=True)


@pytest.fixture(scope="session", autouse=True)
def rebuild_submission():
    assert os.path.isfile(os.path.join(BASE_DIR, "Makefile")), "Makefile is missing."
    assert any(os.path.isfile(os.path.join(BASE_DIR, name)) for name in ("clean_stub.c", "clean_stub.s", "clean_stub.S")), \
        "A clean_stub source file is required."

    # Force Makefile rules to recreate every project-generated object and binary.
    for name in ("server.o", "http_parser.o", "clean_stub.o", "malicious.o", "server_secure"):
        path = os.path.join(BASE_DIR, name)
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    result = subprocess.run(["make"], cwd=BASE_DIR, capture_output=True, text=True)
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert not os.path.exists(os.path.join(BASE_DIR, "malicious.o")), \
        "The rebuild compiled malicious.S/malicious.o."


def test_server_secure_exists_and_executable():
    assert os.path.isfile(SERVER_SECURE), f"File {SERVER_SECURE} does not exist. Did you run make?"
    assert os.access(SERVER_SECURE, os.X_OK), f"File {SERVER_SECURE} is not executable."


def test_symbols_in_executable():
    try:
        result = subprocess.run(["nm", SERVER_SECURE], capture_output=True, text=True, check=True)
        nm_output = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run nm on {SERVER_SECURE}: {e.stderr}")

    assert "init_telemetry_v2" in nm_output, \
        "Symbol 'init_telemetry_v2' is missing from the executable. The stub was not linked correctly."
    assert "malicious_hook" not in nm_output, \
        "Symbol 'malicious_hook' was found in the executable. The malicious code was not removed."


def normalized_object(path, destination):
    run(["objcopy", "--strip-debug", path, destination])
    return open(destination, "rb").read()


def test_required_objects_are_genuine_project_objects():
    for rel in EXPECTED_OBJECTS:
        assert os.path.isfile(os.path.join(BASE_DIR, rel)), f"Required object {rel} was not built."

    # Independently recreate the three fixed project objects and compare them to
    # those used by the submission. This prevents placeholder objects from being
    # substituted for server.o, http_parser.o, or the precompiled vendor object.
    with tempfile.TemporaryDirectory() as td:
        os.mkdir(os.path.join(td, "vendor"))
        shutil.copyfile(os.path.join(BASE_DIR, "server.c"), os.path.join(td, "server.c"))
        shutil.copyfile(os.path.join(BASE_DIR, "http_parser.c"), os.path.join(td, "http_parser.c"))
        with open(os.path.join(td, "vendor", "auth.c"), "w") as f:
            f.write('''#include <stdio.h>\nextern void init_telemetry_v2();\n\nint auth_check() {\n    init_telemetry_v2(); // The problematic dependency\n    return 1;\n}\n''')

        run(["gcc", "-Wall", "-c", "server.c"], cwd=td)
        run(["gcc", "-Wall", "-c", "http_parser.c"], cwd=td)
        run(["gcc", "-c", "vendor/auth.c", "-o", "vendor/auth.o"], cwd=td)

        for rel in ("server.o", "http_parser.o", "vendor/auth.o"):
            submitted = normalized_object(os.path.join(BASE_DIR, rel), os.path.join(td, "submitted.o"))
            expected = normalized_object(os.path.join(td, rel), os.path.join(td, "expected.o"))
            assert submitted == expected, f"{rel} is not the required project object."


def test_clean_stub_is_only_a_noop_function():
    stub = os.path.join(BASE_DIR, "clean_stub.o")
    nm_output = run(["nm", "--defined-only", "--format=posix", stub]).stdout
    defined = [line.split()[0] for line in nm_output.splitlines() if line.strip()]
    assert defined == ["init_telemetry_v2"], \
        f"clean_stub.o must define only init_telemetry_v2, but defines {defined}."

    disassembly = run(["objdump", "-dr", stub]).stdout
    instructions = []
    for line in disassembly.splitlines():
        match = re.match(r"^\s*[0-9a-f]+:\s+(?:[0-9a-f]{2}\s+)+(\S+)(?:\s+(.*?))?\s*$", line)
        if match:
            mnemonic = match.group(1)
            operands = (match.group(2) or "").replace(" ", "")
            instructions.append((mnemonic, operands))

    while instructions and instructions[0][0] == "endbr64":
        instructions.pop(0)

    allowed = [
        [("ret", "")],
        [("nop", ""), ("ret", "")],
        [("push", "%rbp"), ("mov", "%rsp,%rbp"), ("nop", ""), ("pop", "%rbp"), ("ret", "")],
        [("push", "%rbp"), ("mov", "%rsp,%rbp"), ("nop", ""), ("leave", ""), ("ret", "")],
    ]
    assert instructions in allowed, \
        f"init_telemetry_v2 is not a minimal no-op implementation: {instructions}"
    assert "R_" not in disassembly, "The no-op stub must not call or reference other code/data."


def test_binary_is_linked_from_exact_required_objects():
    # Relink the required objects independently. A byte-identical result proves
    # server_secure was not replaced by an unrelated standalone executable.
    with tempfile.TemporaryDirectory() as td:
        expected_binary = os.path.join(td, "server_secure.expected")
        run(["gcc"] + [os.path.join(BASE_DIR, rel) for rel in EXPECTED_OBJECTS] + ["-o", expected_binary])
        with open(SERVER_SECURE, "rb") as f:
            actual = f.read()
        with open(expected_binary, "rb") as f:
            expected = f.read()
        assert actual == expected, \
            "server_secure is not the executable produced by linking the four required objects in order."


def test_dep_graph():
    assert os.path.isfile(DEP_GRAPH), f"File {DEP_GRAPH} does not exist."

    with open(DEP_GRAPH, "r") as f:
        content = f.read().strip()

    files = [f.strip() for f in content.split(",") if f.strip()]
    expected_files = {"server.o", "http_parser.o", "vendor/auth.o", "clean_stub.o"}
    actual_files = set(files)

    assert actual_files == expected_files, \
        f"Expected dependency graph to contain exactly {expected_files}, but got {actual_files}."
    assert "malicious.o" not in actual_files, "malicious.o should not be in the dependency graph."
    assert files == EXPECTED_OBJECTS, \
        f"Dependency graph must list the direct link inputs once and in link order: {EXPECTED_OBJECTS}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
