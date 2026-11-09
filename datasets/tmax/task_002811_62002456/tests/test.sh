#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import subprocess
import sys
import tempfile

import grpc


def test_files_exist():
    assert os.path.isfile("/home/user/evaluator.proto"), "File /home/user/evaluator.proto is missing"
    assert os.path.isfile("/home/user/server.py"), "File /home/user/server.py is missing"
    assert os.path.isfile("/home/user/test_pbt.py"), "File /home/user/test_pbt.py is missing"


def compile_proto(tmpdir):
    proto_path = "/home/user/evaluator.proto"
    assert os.path.isfile(proto_path), "evaluator.proto does not exist."
    cmd = [
        sys.executable, "-m", "grpc_tools.protoc",
        f"--proto_path={os.path.dirname(proto_path)}",
        f"--python_out={tmpdir}",
        f"--grpc_python_out={tmpdir}",
        proto_path,
    ]
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        assert False, f"Failed to compile protobuf:\n{e.stderr}"

    sys.path.insert(0, tmpdir)
    try:
        import evaluator_pb2
        import evaluator_pb2_grpc
        return evaluator_pb2, evaluator_pb2_grpc
    except ImportError as e:
        assert False, f"Failed to import generated protobuf modules: {e}"
    finally:
        sys.path.pop(0)


def test_grpc_server_accuracy():
    with tempfile.TemporaryDirectory() as tmpdir:
        evaluator_pb2, evaluator_pb2_grpc = compile_proto(tmpdir)
        channel = grpc.insecure_channel("localhost:50051")
        stub = evaluator_pb2_grpc.EvaluatorStub(channel)

        test_cases = [
            {"expr": "A + B * C", "data": {"A": 2, "B": 3, "C": 4}, "expected": 14},
            {"expr": "(A + B) * C", "data": {"A": 2, "B": 3, "C": 4}, "expected": 20},
            {"expr": "Z * Z - Y", "data": {"Z": 10, "Y": 5}, "expected": 95},
            {"expr": "A * (B - C) + D", "data": {"A": 5, "B": 10, "C": 2, "D": 1}, "expected": 41},
            {"expr": "X * Y * Z", "data": {"X": 2, "Y": -3, "Z": 4}, "expected": -24},
        ]

        correct = 0
        total = len(test_cases)
        for case in test_cases:
            try:
                req = evaluator_pb2.EvalRequest(expr=case["expr"], data=case["data"])
                resp = stub.Evaluate(req, timeout=2.0)
                if resp.result == case["expected"]:
                    correct += 1
            except Exception:
                pass

        accuracy = correct / total
        assert accuracy >= 1.0, f"Accuracy metric failed: {accuracy} < 1.0"
        channel.close()


def make_expression(rng, depth, variables):
    if depth <= 0 or rng.random() < 0.24:
        return rng.choice(variables)
    left = make_expression(rng, depth - 1, variables)
    right = make_expression(rng, depth - 1, variables)
    op = rng.choice(["+", "-", "*"])
    expr = f"{left} {op} {right}"
    if rng.random() < 0.78:
        expr = f"({expr})"
    return expr


def legacy_result(expr, data):
    request = json.dumps({"expr": expr, "data": data})
    proc = subprocess.run(
        ["/app/legacy_evaluator"],
        input=request,
        text=True,
        capture_output=True,
        timeout=3,
        check=True,
    )
    response = json.loads(proc.stdout)
    assert "result" in response, f"Legacy evaluator failed for {expr!r}: {response}"
    return response["result"]


def test_grpc_server_randomized_against_legacy():
    # A fresh unpredictable seed prevents implementations from special-casing a fixed corpus.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    with tempfile.TemporaryDirectory() as tmpdir:
        evaluator_pb2, evaluator_pb2_grpc = compile_proto(tmpdir)
        channel = grpc.insecure_channel("localhost:50051")
        grpc.channel_ready_future(channel).result(timeout=5)
        stub = evaluator_pb2_grpc.EvaluatorStub(channel)

        checked = 0
        attempts = 0
        while checked < 80 and attempts < 400:
            attempts += 1
            variables = rng.sample(list("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), rng.randint(2, 8))
            expr = make_expression(rng, rng.randint(2, 4), variables)
            # Omit some variables deliberately: the legacy evaluator treats them as zero.
            data = {
                name: rng.randint(-7, 7)
                for name in variables
                if rng.random() < 0.82
            }
            expected = legacy_result(expr, data)
            if not -(2**31) <= expected < 2**31:
                continue
            req = evaluator_pb2.EvalRequest(expr=expr, data=data)
            resp = stub.Evaluate(req, timeout=3.0)
            assert resp.result == expected, (
                f"Mismatch for expression {expr!r} with data {data}: "
                f"got {resp.result}, expected {expected}"
            )
            checked += 1

        assert checked == 80, f"Only generated {checked} usable randomized cases"
        channel.close()


def test_property_based_test_script_is_real_and_passes():
    path = "/home/user/test_pbt.py"
    source = open(path, "r", encoding="utf-8").read()
    assert source.strip(), "test_pbt.py is empty"
    tree = ast.parse(source, filename=path)

    imports_hypothesis = any(
        (isinstance(node, ast.Import) and any(a.name == "hypothesis" or a.name.startswith("hypothesis.") for a in node.names))
        or (isinstance(node, ast.ImportFrom) and (node.module or "").startswith("hypothesis"))
        for node in ast.walk(tree)
    )

    def is_given(decorator):
        target = decorator.func if isinstance(decorator, ast.Call) else decorator
        return (
            isinstance(target, ast.Name) and target.id == "given"
        ) or (
            isinstance(target, ast.Attribute) and target.attr == "given"
        )

    has_given_test = any(
        isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and any(is_given(d) for d in node.decorator_list)
        for node in ast.walk(tree)
    )
    has_assertion = any(
        isinstance(node, ast.Assert)
        or (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr.startswith("assert")
        )
        for node in ast.walk(tree)
    )
    assert imports_hypothesis, "test_pbt.py must import hypothesis"
    assert has_given_test, "test_pbt.py must contain a Hypothesis @given property test"
    assert has_assertion, "test_pbt.py must assert that evaluator outputs match"

    harness = r'''
import subprocess
import sys
import grpc
import pytest

state = {"active": False, "legacy": 0, "rpc": 0, "hypothesis_items": 0}
original_popen = subprocess.Popen
original_channel = grpc.insecure_channel


def tracked_popen(*args, **kwargs):
    command = kwargs.get("args", args[0] if args else None)
    if state["active"] and "/app/legacy_evaluator" in str(command):
        state["legacy"] += 1
    return original_popen(*args, **kwargs)


class RpcCallableProxy:
    def __init__(self, wrapped):
        self._wrapped = wrapped

    def __call__(self, *args, **kwargs):
        if state["active"]:
            state["rpc"] += 1
        return self._wrapped(*args, **kwargs)

    def with_call(self, *args, **kwargs):
        if state["active"]:
            state["rpc"] += 1
        return self._wrapped.with_call(*args, **kwargs)

    def future(self, *args, **kwargs):
        if state["active"]:
            state["rpc"] += 1
        return self._wrapped.future(*args, **kwargs)


class ChannelProxy:
    def __init__(self, wrapped):
        self._wrapped = wrapped

    def unary_unary(self, *args, **kwargs):
        return RpcCallableProxy(self._wrapped.unary_unary(*args, **kwargs))

    def __getattr__(self, name):
        return getattr(self._wrapped, name)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self._wrapped.close()


def tracked_channel(*args, **kwargs):
    return ChannelProxy(original_channel(*args, **kwargs))


subprocess.Popen = tracked_popen
grpc.insecure_channel = tracked_channel


class Plugin:
    def pytest_collection_modifyitems(self, session, config, items):
        for item in items:
            if getattr(getattr(item, "obj", None), "is_hypothesis_test", False):
                state["hypothesis_items"] += 1

    def pytest_runtest_setup(self, item):
        state["active"] = bool(getattr(getattr(item, "obj", None), "is_hypothesis_test", False))

    def pytest_runtest_teardown(self, item, nextitem):
        state["active"] = False


rc = pytest.main(["-q", "/home/user/test_pbt.py"], plugins=[Plugin()])
if rc != 0:
    raise SystemExit(f"property-based tests failed with pytest status {rc}")
if state["hypothesis_items"] < 1:
    raise SystemExit("pytest did not collect a Hypothesis property test")
if state["legacy"] < 5:
    raise SystemExit(f"Hypothesis test invoked the legacy evaluator only {state['legacy']} times")
if state["rpc"] < 5:
    raise SystemExit(f"Hypothesis test made only {state['rpc']} gRPC calls")
'''
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
        f.write(harness)
        harness_path = f.name
    try:
        proc = subprocess.run(
            [sys.executable, harness_path],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=180,
        )
    finally:
        os.unlink(harness_path)
    assert proc.returncode == 0, (
        "Required property-based test script did not pass or did not exercise both implementations.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
