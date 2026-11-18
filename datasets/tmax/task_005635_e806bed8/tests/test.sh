#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import os
import signal
import subprocess
import sys

import pytest

REPO = "/home/user/repo"


def load_vm_class():
    path = os.path.join(REPO, "assembler.py")
    assert os.path.isfile(path), "assembler.py is missing."
    spec = importlib.util.spec_from_file_location("submitted_assembler", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "AssemblerVM"), "assembler.py does not define AssemblerVM."
    return module.AssemblerVM


def run_with_timeout(fn, seconds=3):
    def timed_out(signum, frame):
        raise TimeoutError("VM execution did not terminate")

    previous = signal.signal(signal.SIGALRM, timed_out)
    signal.alarm(seconds)
    try:
        return fn()
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)


def test_assembler_fixed():
    """Retain the source checks and verify absolute JNZ behavior directly."""
    file_path = os.path.join(REPO, "assembler.py")
    assert os.path.isfile(file_path), "assembler.py is missing."
    with open(file_path, "r") as f:
        content = f.read()

    content_no_spaces = content.replace(" ", "")
    assert "self.pc=int(parts[1])" in content_no_spaces, (
        "The JNZ instruction does not perform an absolute jump "
        "(self.pc = int(parts[1]))."
    )
    assert "self.pc+=int(parts[1])" not in content_no_spaces, (
        "The JNZ instruction still contains the relative jump bug."
    )

    AssemblerVM = load_vm_class()

    # In each case JNZ is at line 1 and its destination is the final line.
    # A relative implementation jumps beyond the program instead.
    for destination, marker in ((3, 137), (6, -42), (9, 811)):
        lines = ["PUSH 1", f"JNZ {destination}"]
        lines.extend(f"PUSH {1000 + i}" for i in range(2, destination))
        lines.append(f"PUSH {marker}")
        vm = AssemblerVM()
        run_with_timeout(lambda: vm.run("\n".join(lines)))
        assert vm.stack == [marker], (
            f"JNZ did not jump to absolute line {destination}; stack was {vm.stack}."
        )

    # A false JNZ must pop its condition and continue to the following line.
    vm = AssemblerVM()
    run_with_timeout(lambda: vm.run("PUSH 0\nJNZ 3\nPUSH 73"))
    assert vm.stack == [73], "JNZ handled a zero condition incorrectly."


def execute_independently(code):
    """Execute program.asm with an independent implementation of the specified ISA."""
    lines = code.split("\n")
    stack = []
    memory = {}
    pc = 0
    steps = 0
    add_operands = []

    while pc < len(lines):
        assert pc >= 0, f"Program jumped to invalid negative line {pc}."
        steps += 1
        assert steps <= 10000, "program.asm did not terminate within 10000 instructions."

        line = lines[pc].strip()
        if not line or line.startswith("#"):
            pc += 1
            continue

        parts = line.split()
        op = parts[0]
        if op == "PUSH":
            assert len(parts) == 2
            stack.append(int(parts[1]))
        elif op == "POP":
            assert len(parts) == 1
            stack.pop()
        elif op == "ADD":
            assert len(parts) == 1
            a = stack.pop()
            b = stack.pop()
            add_operands.append((b, a))
            stack.append(a + b)
        elif op == "SUB":
            assert len(parts) == 1
            a = stack.pop()
            b = stack.pop()
            stack.append(b - a)
        elif op == "STORE":
            assert len(parts) == 2
            memory[parts[1]] = stack.pop()
        elif op == "LOAD":
            assert len(parts) == 2
            stack.append(memory.get(parts[1], 0))
        elif op == "JMP":
            assert len(parts) == 2
            pc = int(parts[1])
            continue
        elif op == "JNZ":
            assert len(parts) == 2
            value = stack.pop()
            if value != 0:
                pc = int(parts[1])
                continue
        else:
            pytest.fail(f"Unknown instruction in program.asm at line {pc}: {op}")
        pc += 1

    return stack, add_operands


def test_program_asm_output():
    asm_path = os.path.join(REPO, "program.asm")
    assert os.path.isfile(asm_path), "program.asm is missing."
    with open(asm_path, "r") as f:
        code = f.read()

    # Independently establish that the submitted program performs the requested
    # additions rather than merely containing PUSH 15.
    stack, add_operands = execute_independently(code)
    assert stack == [15], f"Expected the final stack to be exactly [15], got {stack}."
    assert len(add_operands) >= 4, (
        "program.asm must calculate the sum, not merely push the constant 15."
    )
    observed_add_values = {value for pair in add_operands for value in pair}
    assert set(range(1, 6)).issubset(observed_add_values), (
        "The executed additions do not account for the countdown values 5 through 1."
    )

    # Retain the original requirement that the submitted VM itself runs the file.
    AssemblerVM = load_vm_class()
    vm = AssemblerVM()
    try:
        run_with_timeout(lambda: vm.run(code))
    except Exception as exc:
        pytest.fail(f"Execution of program.asm failed with an exception: {exc}")
    assert len(vm.stack) > 0, "The stack is empty after running program.asm."
    assert vm.stack[-1] == 15, f"Expected 15 on top, but got {vm.stack[-1]}."
    assert vm.stack == [15], f"15 must be the only final stack value, got {vm.stack}."


def test_test_assembler_passes():
    """Ensure the repaired unittest suite still exists, is collected, and passes."""
    file_path = os.path.join(REPO, "test_assembler.py")
    assert os.path.isfile(file_path), "test_assembler.py is missing."

    with open(file_path, "r") as f:
        tree = ast.parse(f.read(), filename=file_path)

    basic_test = None
    jnz_test = None
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            if node.name == "test_basic_addition":
                basic_test = node
            elif node.name == "test_jnz":
                jnz_test = node

    assert basic_test is not None, "test_basic_addition was removed."
    assert jnz_test is not None, "test_jnz was removed."
    assert len(basic_test.args.args) >= 2, (
        "test_basic_addition must accept the mock injected by @patch('sys.stdout')."
    )

    patches_stdout = False
    for decorator in basic_test.decorator_list:
        if isinstance(decorator, ast.Call) and decorator.args:
            func_name = decorator.func.id if isinstance(decorator.func, ast.Name) else None
            arg = decorator.args[0]
            if (func_name == "patch" and isinstance(arg, ast.Constant)
                    and arg.value == "sys.stdout"):
                patches_stdout = True
    assert patches_stdout, "test_basic_addition must retain @patch('sys.stdout')."

    collected = subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", "-q", file_path],
        capture_output=True,
        text=True,
        timeout=30,
        cwd=REPO,
    )
    assert collected.returncode == 0, collected.stdout + collected.stderr
    collection_output = collected.stdout + collected.stderr
    assert "test_basic_addition" in collection_output
    assert "test_jnz" in collection_output

    result = subprocess.run(
        [sys.executable, "-m", "pytest", file_path],
        capture_output=True,
        text=True,
        timeout=30,
        cwd=REPO,
    )
    assert result.returncode == 0, (
        "Tests in test_assembler.py failed to pass. Output:\n"
        f"{result.stdout}\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
