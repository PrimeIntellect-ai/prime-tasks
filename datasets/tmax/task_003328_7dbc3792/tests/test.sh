#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import stat
import subprocess
import tempfile

import pytest

BASE = "/home/user/migration"
PROCESS = os.path.join(BASE, "process.py")
ORCHESTRATOR = os.path.join(BASE, "orchestrator.py")


def run_checked(command, *, cwd=BASE, env=None):
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {command}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def remove_generated_outputs():
    for name in ("final_output.txt", "diff_result.txt", "execution_order.txt"):
        path = os.path.join(BASE, name)
        if os.path.exists(path):
            os.remove(path)
    for name in (
        "data_A.txt", "data_B.txt", "data_C.txt",
        "data_D.txt", "data_E.txt", "data_F.txt",
    ):
        path = os.path.join(BASE, name + ".out")
        if os.path.exists(path):
            os.remove(path)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(ORCHESTRATOR), f"Python script {ORCHESTRATOR} is missing."
    remove_generated_outputs()
    run_checked(["python3", ORCHESTRATOR])


def test_process_py_syntax():
    script_path = PROCESS
    assert os.path.isfile(script_path), f"Python script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert "print " not in content, "process.py still contains Python 2 print statements."
    assert "xrange" not in content, "process.py still contains Python 2 xrange."

    try:
        ast.parse(content)
    except SyntaxError as e:
        pytest.fail(f"process.py contains a Python 3 syntax error: {e}")


def test_libprocessor_so_exists_and_is_loadable():
    # Preserve the original recursive existence assertion.
    candidates = []
    for root, dirs, files in os.walk(BASE):
        if "libprocessor.so" in files:
            candidates.append(os.path.join(root, "libprocessor.so"))
    assert candidates, "libprocessor.so was not found. The CMake project was not compiled correctly."

    usable = []
    errors = []
    for path in candidates:
        try:
            with open(path, "rb") as f:
                assert f.read(4) == b"\x7fELF", f"{path} is not an ELF shared library."
            library = ctypes.CDLL(path)
            assert hasattr(library, "process_buffer"), f"{path} lacks process_buffer."
            usable.append(path)
        except Exception as exc:
            errors.append(f"{path}: {exc}")
    assert usable, "No usable libprocessor.so was found:\n" + "\n".join(errors)


def test_process_py_actually_uses_the_processor():
    with tempfile.TemporaryDirectory() as tmpdir:
        probe = os.path.join(tmpdir, "probe.txt")
        with open(probe, "w") as f:
            f.write("AZby9\n")

        run_checked(["python3", PROCESS, probe])
        output = probe + ".out"
        assert os.path.isfile(output), "process.py did not create the required .out file."
        with open(output, "r") as f:
            assert f.read() == "B[by9\n", "process.py did not apply the C processor correctly."


def test_diff_result_empty():
    diff_path = os.path.join(BASE, "diff_result.txt")
    assert os.path.isfile(diff_path), f"{diff_path} is missing."

    with open(diff_path, "r") as f:
        content = f.read().strip()

    assert content == "", f"diff_result.txt is not empty. Differences found:\n{content}"

    # Do not trust the submitted diff_result.txt; perform the comparison ourselves.
    result = subprocess.run(
        ["diff", os.path.join(BASE, "expected_output.txt"), os.path.join(BASE, "final_output.txt")],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"final_output.txt differs from expected_output.txt:\n{result.stdout}{result.stderr}"


def test_execution_order_valid():
    order_path = os.path.join(BASE, "execution_order.txt")
    assert os.path.isfile(order_path), f"{order_path} is missing."

    with open(order_path, "r") as f:
        content = f.read().strip()

    order = [x.strip() for x in content.split(",") if x.strip()]

    expected_files = {
        "data_A.txt", "data_B.txt", "data_C.txt",
        "data_D.txt", "data_E.txt", "data_F.txt",
    }

    assert set(order) == expected_files, f"execution_order.txt does not contain exactly the required files. Found: {order}"

    def assert_before(dep, target):
        assert order.index(dep) < order.index(target), f"Topological sort failed: {dep} must be executed before {target}"

    assert_before("data_A.txt", "data_B.txt")
    assert_before("data_A.txt", "data_D.txt")
    assert_before("data_B.txt", "data_C.txt")
    assert_before("data_D.txt", "data_E.txt")
    assert_before("data_C.txt", "data_F.txt")
    assert_before("data_E.txt", "data_F.txt")


def test_final_output_exists():
    output_path = os.path.join(BASE, "final_output.txt")
    assert os.path.isfile(output_path), f"{output_path} is missing."

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 6, f"final_output.txt should contain 6 lines, but found {len(lines)}."


def test_orchestrator_handles_changed_graph_and_invokes_process():
    names = [
        "data_A.txt", "data_B.txt", "data_C.txt",
        "data_D.txt", "data_E.txt", "data_F.txt",
    ]
    state_paths = [
        os.path.join(BASE, "deps.txt"),
        os.path.join(BASE, "expected_output.txt"),
        PROCESS,
    ]
    state_paths += [os.path.join(BASE, name) for name in names]
    state_paths += [os.path.join(BASE, name + ".out") for name in names]
    state_paths += [os.path.join(BASE, name) for name in (
        "final_output.txt", "diff_result.txt", "execution_order.txt"
    )]

    saved = {}
    modes = {}
    for path in state_paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = f.read()
            modes[path] = stat.S_IMODE(os.stat(path).st_mode)
        else:
            saved[path] = None

    backup_process = os.path.join(BASE, ".process.py.verifier-original")
    fd, invocation_log = tempfile.mkstemp(prefix="orchestrator-invocations-")
    os.close(fd)

    chain = [
        "data_F.txt", "data_C.txt", "data_A.txt",
        "data_E.txt", "data_B.txt", "data_D.txt",
    ]
    values = {
        "data_A.txt": "ALPHA9",
        "data_B.txt": "BRAVO8",
        "data_C.txt": "CHARLIE7",
        "data_D.txt": "DELTA6",
        "data_E.txt": "ECHO5",
        "data_F.txt": "FOXTROT4",
    }

    def transformed(value):
        return "".join(chr(ord(ch) + 1) if "A" <= ch <= "Z" else ch for ch in value)

    try:
        with open(PROCESS, "rb") as src, open(backup_process, "wb") as dst:
            dst.write(src.read())
        os.chmod(backup_process, modes[PROCESS])

        wrapper = f'''#!/usr/bin/env python3
import os
import sys
log = os.environ.get("VERIFIER_PROCESS_LOG")
if log:
    with open(log, "a") as f:
        f.write((sys.argv[1] if len(sys.argv) > 1 else "") + "\\n")
os.execv(sys.executable, [sys.executable, {backup_process!r}] + sys.argv[1:])
'''
        with open(PROCESS, "w") as f:
            f.write(wrapper)
        os.chmod(PROCESS, modes[PROCESS])

        with open(os.path.join(BASE, "deps.txt"), "w") as f:
            for previous, current in zip(chain, chain[1:]):
                f.write(f"{current} depends on {previous}\n")

        for name, value in values.items():
            with open(os.path.join(BASE, name), "w") as f:
                f.write(value + "\n")

        expected = "".join(transformed(values[name]) + "\n" for name in chain)
        with open(os.path.join(BASE, "expected_output.txt"), "w") as f:
            f.write(expected)

        remove_generated_outputs()
        env = os.environ.copy()
        env["VERIFIER_PROCESS_LOG"] = invocation_log
        run_checked(["python3", ORCHESTRATOR], env=env)

        with open(invocation_log, "r") as f:
            invoked = [os.path.basename(line.strip()) for line in f if line.strip()]
        assert invoked == chain, f"orchestrator.py did not execute process.py once per file in topological order: {invoked}"

        with open(os.path.join(BASE, "execution_order.txt"), "r") as f:
            dynamic_order = [part.strip() for part in f.read().strip().split(",") if part.strip()]
        assert dynamic_order == chain, f"Incorrect order for changed dependency graph: {dynamic_order}"

        with open(os.path.join(BASE, "final_output.txt"), "r") as f:
            actual = f.read()
        assert actual == expected, f"Incorrect dynamically generated final output: {actual!r}"

        with open(os.path.join(BASE, "diff_result.txt"), "r") as f:
            assert f.read() == "", "diff_result.txt was not empty for matching dynamic output."

        for name in names:
            output = os.path.join(BASE, name + ".out")
            assert os.path.isfile(output), f"orchestrator did not produce {output}."
            with open(output, "r") as f:
                assert f.read() == transformed(values[name]) + "\n"
    finally:
        if os.path.exists(backup_process):
            os.remove(backup_process)
        if os.path.exists(invocation_log):
            os.remove(invocation_log)
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
                os.chmod(path, modes[path])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
