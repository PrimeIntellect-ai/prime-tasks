#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import math
import os
import random
import subprocess
import sys
import pytest

SCRIPT = "/home/user/simulation/simulate.py"
RESULT = "/home/user/result.json"


def load_submission():
    spec = importlib.util.spec_from_file_location("submitted_simulate", SCRIPT)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def reference_kinematics(forces):
    velocity = 5.0
    dt = 0.1
    mass = 2.0
    position = 0.0
    for force in forces:
        acceleration = force / mass
        velocity += acceleration * dt
        if velocity < 0.0:
            velocity = 0.0
        assert velocity >= 0.0, "Velocity cannot be negative"
        position += velocity * dt
    return position


def test_execute_script():
    """The submitted artifact itself must run and freshly generate the result."""
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user/simulation",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, completed.stderr
    assert os.path.isfile(RESULT), "The executed script did not generate result.json."


def test_result_file_exists():
    """Test that the result.json file was generated."""
    file_path = "/home/user/result.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. Did you run the script?"


def test_result_content_correct():
    """Test that the result.json contains the correct final position."""
    file_path = "/home/user/result.json"
    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert "final_position" in data, "Key 'final_position' is missing from result.json."

    expected_position = 1.25
    actual_position = data["final_position"]

    assert isinstance(actual_position, (int, float)), "final_position must be a number."
    assert math.isclose(actual_position, expected_position, rel_tol=1e-5, abs_tol=1e-5), \
        f"Expected final_position to be close to {expected_position}, but got {actual_position}."


def test_simulate_script_fixes():
    """Test that the simulate.py script has the required fixes."""
    file_path = "/home/user/simulation/simulate.py"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, 'r') as f:
        content = f.read()

    # Keep the original source assertions.
    assert "len(forces) - 1" not in content, "The off-by-one error (len(forces) - 1) is still present."
    assert "assert velocity >= 0.0" in content, "The required assertion 'assert velocity >= 0.0' is missing."


def test_required_logic_is_executable_and_in_order():
    """Ensure the clamp and exact assertion are real statements in the processing loop."""
    with open(SCRIPT, "r") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    functions = [
        node for node in tree.body
        if isinstance(node, ast.FunctionDef) and node.name == "process_kinematics"
    ]
    assert len(functions) == 1, "process_kinematics must be defined exactly once."
    function = functions[0]

    loops = [node for node in function.body if isinstance(node, ast.For)]
    assert loops, "process_kinematics must contain its force-processing loop."

    valid_loop = None
    for loop in loops:
        iterator_ok = False
        if isinstance(loop.iter, ast.Name) and loop.iter.id == "forces":
            iterator_ok = True
        elif isinstance(loop.iter, ast.Call) and isinstance(loop.iter.func, ast.Name):
            if loop.iter.func.id == "enumerate" and loop.iter.args and isinstance(loop.iter.args[0], ast.Name) and loop.iter.args[0].id == "forces":
                iterator_ok = True
            if loop.iter.func.id == "range" and len(loop.iter.args) == 1:
                arg = loop.iter.args[0]
                iterator_ok = (
                    isinstance(arg, ast.Call)
                    and isinstance(arg.func, ast.Name)
                    and arg.func.id == "len"
                    and len(arg.args) == 1
                    and isinstance(arg.args[0], ast.Name)
                    and arg.args[0].id == "forces"
                )
        if not iterator_ok:
            continue

        body = loop.body
        for index in range(len(body) - 2):
            update = body[index]
            clamp = body[index + 1]
            assertion = body[index + 2]

            update_ok = (
                isinstance(update, ast.AugAssign)
                and isinstance(update.target, ast.Name)
                and update.target.id == "velocity"
                and isinstance(update.op, ast.Add)
            )
            clamp_ok = (
                isinstance(clamp, ast.If)
                and isinstance(clamp.test, ast.Compare)
                and isinstance(clamp.test.left, ast.Name)
                and clamp.test.left.id == "velocity"
                and len(clamp.test.ops) == 1
                and isinstance(clamp.test.ops[0], ast.Lt)
                and len(clamp.test.comparators) == 1
                and isinstance(clamp.test.comparators[0], ast.Constant)
                and clamp.test.comparators[0].value == 0.0
                and len(clamp.body) == 1
                and isinstance(clamp.body[0], ast.Assign)
                and len(clamp.body[0].targets) == 1
                and isinstance(clamp.body[0].targets[0], ast.Name)
                and clamp.body[0].targets[0].id == "velocity"
                and isinstance(clamp.body[0].value, ast.Constant)
                and clamp.body[0].value.value == 0.0
                and not clamp.orelse
            )
            assertion_ok = (
                isinstance(assertion, ast.Assert)
                and isinstance(assertion.test, ast.Compare)
                and isinstance(assertion.test.left, ast.Name)
                and assertion.test.left.id == "velocity"
                and len(assertion.test.ops) == 1
                and isinstance(assertion.test.ops[0], ast.GtE)
                and len(assertion.test.comparators) == 1
                and isinstance(assertion.test.comparators[0], ast.Constant)
                and assertion.test.comparators[0].value == 0.0
                and isinstance(assertion.msg, ast.Constant)
                and assertion.msg.value == "Velocity cannot be negative"
            )
            if update_ok and clamp_ok and assertion_ok:
                valid_loop = loop
                break
        if valid_loop is not None:
            break

    assert valid_loop is not None, (
        "The loop must update velocity, immediately clamp it when below 0.0, "
        "and then execute the exact required assertion."
    )

    assertion_index = next(i for i, node in enumerate(valid_loop.body) if isinstance(node, ast.Assert))
    position_updates = [
        i for i, node in enumerate(valid_loop.body)
        if isinstance(node, ast.Expr)
        and isinstance(node.value, ast.Call)
        and isinstance(node.value.func, ast.Attribute)
        and isinstance(node.value.func.value, ast.Name)
        and node.value.func.value.id == "positions"
        and node.value.func.attr == "append"
    ]
    assert position_updates and all(i > assertion_index for i in position_updates), \
        "The assertion must occur before the position update."


def test_process_kinematics_on_derived_inputs():
    """Exercise all-force processing and clamping on answers derived at test time."""
    module = load_submission()
    assert callable(getattr(module, "process_kinematics", None))

    cases = [
        [],
        [0.0],
        [-200.0],
        [10.0, -500.0, 20.0],
        [0.0, 0.0, 0.0, 80.0],
        [-50.0, -100.0, -20.0, 20.0, 40.0, 60.0],
    ]
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    for _ in range(25):
        length = rng.randint(1, 18)
        cases.append([rng.uniform(-250.0, 250.0) for _ in range(length)])

    for forces in cases:
        expected = reference_kinematics(forces)
        actual = module.process_kinematics(list(forces))
        assert isinstance(actual, (int, float)), "process_kinematics must return a number."
        assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), \
            f"Incorrect result for forces={forces!r}: expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
