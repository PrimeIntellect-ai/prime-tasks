#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
import sys
import time

import grpc
import pytest

SERVICE_DIR = "/home/user/math_service"
DATA_PATH = "/home/user/test_data.json"
RESULTS_PATH = "/home/user/test_results.json"
E2E_PATH = os.path.join(SERVICE_DIR, "e2e_test.py")


@pytest.fixture(scope="session", autouse=True)
def running_server():
    # Do not allow an agent-left background process to stand in for server.py.
    subprocess.run(
        ["pkill", "-f", "/home/user/math_service/server.py"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    time.sleep(0.2)

    proc = subprocess.Popen(
        [sys.executable, os.path.join(SERVICE_DIR, "server.py")],
        cwd=SERVICE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    channel = grpc.insecure_channel("127.0.0.1:50051")
    try:
        grpc.channel_ready_future(channel).result(timeout=10)
    except Exception:
        proc.terminate()
        try:
            output, _ = proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            output, _ = proc.communicate()
        pytest.fail("server.py did not start a usable gRPC server. Output:\n" + output)

    yield channel

    channel.close()
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)


def test_protobuf_compiled():
    pb2_path = "/home/user/math_service/math_service_pb2.py"
    pb2_grpc_path = "/home/user/math_service/math_service_pb2_grpc.py"

    assert os.path.isfile(pb2_path), f"Protobuf python file {pb2_path} is missing. Did you compile the proto file?"
    assert os.path.isfile(pb2_grpc_path), f"Protobuf grpc python file {pb2_grpc_path} is missing. Did you compile the proto file?"
    assert os.path.getsize(pb2_path) > 0, f"Protobuf python file {pb2_path} is empty."
    assert os.path.getsize(pb2_grpc_path) > 0, f"Protobuf grpc python file {pb2_grpc_path} is empty."


def test_server_evaluates_generated_requests(running_server):
    sys.path.insert(0, SERVICE_DIR)
    try:
        import math_service_pb2
        import math_service_pb2_grpc
    finally:
        if sys.path[0] == SERVICE_DIR:
            sys.path.pop(0)

    stub = math_service_pb2_grpc.PostfixEvaluatorStub(running_server)

    left = secrets.randbelow(30) + 11
    right = secrets.randbelow(8) + 2
    quotient = secrets.randbelow(12) + 2
    divisor = secrets.randbelow(8) + 2
    base = secrets.randbelow(4) + 2
    exponent = secrets.randbelow(3) + 2
    fact = secrets.randbelow(4) + 4

    cases = [
        (f"{left} {right} +", float(left + right)),
        (f"{left} {right} -", float(left - right)),
        (f"{left} {right} *", float(left * right)),
        (f"{quotient * divisor} {divisor} /", float(quotient)),
        (f"{base} {exponent} ^", float(base ** exponent)),
        (f"{fact} !", float(math.factorial(fact))),
        (f"{fact} ! {right} + 2 /", (math.factorial(fact) + right) / 2.0),
    ]

    for expression, expected in cases:
        response = stub.Evaluate(
            math_service_pb2.EvaluateRequest(expression=expression), timeout=5
        )
        assert response.error == "", f"Unexpected error for {expression!r}: {response.error}"
        assert math.isclose(response.result, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"Wrong result for {expression!r}: expected {expected}, got {response.result}"
        )

    for expression in ("", "+", "1 2", "2 +", "not-a-number 3 +", "4 0 /"):
        response = stub.Evaluate(
            math_service_pb2.EvaluateRequest(expression=expression), timeout=5
        )
        assert response.error, f"Invalid expression {expression!r} did not return an error string"


def _run_e2e():
    assert os.path.isfile(E2E_PATH), f"E2E orchestrator {E2E_PATH} is missing."
    if os.path.exists(RESULTS_PATH):
        os.unlink(RESULTS_PATH)

    try:
        completed = subprocess.run(
            [sys.executable, E2E_PATH],
            cwd=SERVICE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"e2e_test.py did not finish within 30 seconds. Output:\n{exc.stdout or ''}")

    assert completed.returncode == 0, (
        f"e2e_test.py exited with status {completed.returncode}. Output:\n{completed.stdout}"
    )
    assert os.path.isfile(RESULTS_PATH), "e2e_test.py did not create test_results.json"


def _load_results():
    with open(RESULTS_PATH, "r") as f:
        return json.load(f)


def _assert_results_match(results, dataset):
    assert isinstance(results, list)
    assert len(results) == len(dataset)

    for index, (result, case) in enumerate(zip(results, dataset)):
        assert isinstance(result, dict), f"Result {index} is not an object"
        assert set(result) == {"expression", "expected", "actual", "status"}, (
            f"Result {index} does not have the exact required keys"
        )
        assert result["expression"] == case["expression"], f"Expression mismatch at result {index}"
        assert result["expected"] == case["expected"], f"Expected-value mismatch at result {index}"

        expected = case["expected"]
        if expected is None:
            assert result["actual"] is None, f"Expected an error/null actual at result {index}"
        else:
            assert isinstance(result["actual"], (int, float)) and not isinstance(result["actual"], bool), (
                f"Actual value at result {index} is not numeric"
            )
            assert math.isclose(float(result["actual"]), float(expected), rel_tol=1e-12, abs_tol=1e-12), (
                f"Actual-value mismatch at result {index}: expected {expected}, got {result['actual']}"
            )
        assert result["status"] == "PASS", f"Result {index} is not marked PASS"


def test_e2e_orchestrator_on_generated_and_original_data(running_server):
    with open(DATA_PATH, "rb") as f:
        original_bytes = f.read()
    original_data = json.loads(original_bytes.decode("utf-8"))

    a = secrets.randbelow(20) + 10
    b = secrets.randbelow(7) + 2
    n = secrets.randbelow(4) + 4
    hidden_data = [
        {"expression": f"{a} {b} -", "expected": float(a - b)},
        {"expression": f"{a * b} {b} /", "expected": float(a)},
        {"expression": f"{n} !", "expected": float(math.factorial(n))},
        {"expression": f"{a} {b} + 3 *", "expected": float((a + b) * 3)},
        {"expression": "1 2 3 +", "expected": None},
    ]

    try:
        with open(DATA_PATH, "w") as f:
            json.dump(hidden_data, f)
        _run_e2e()
        _assert_results_match(_load_results(), hidden_data)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_bytes)

    _run_e2e()
    _assert_results_match(_load_results(), original_data)


def test_test_results_exists_and_valid():
    results_path = "/home/user/test_results.json"
    data_path = "/home/user/test_data.json"

    assert os.path.isfile(results_path), f"Results file {results_path} is missing. Did the E2E script generate it?"

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Results file {results_path} is not valid JSON.")

    assert isinstance(results, list), "Results in test_results.json should be a JSON array."
    assert len(results) > 0, "Results array is empty."

    with open(data_path, 'r') as f:
        test_data = json.load(f)

    assert len(results) == len(test_data), f"Expected {len(test_data)} results, but found {len(results)}."

    # Check that all tests passed and match the expected schema
    for res in results:
        assert "expression" in res, "Result object is missing 'expression' key."
        assert "expected" in res, "Result object is missing 'expected' key."
        assert "actual" in res, "Result object is missing 'actual' key."
        assert "status" in res, "Result object is missing 'status' key."

        assert res["status"] == "PASS", (
            f"Test failed for expression: '{res.get('expression')}'. "
            f"Expected: {res.get('expected')}, Actual: {res.get('actual')}"
        )

    _assert_results_match(results, test_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
