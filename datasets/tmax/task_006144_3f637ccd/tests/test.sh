#!/bin/bash
set +e
mkdir -p /logs/verifier

(
    set -e
    WORKSPACE=/home/user/workspace
    cd "$WORKSPACE"

    # Ensure the requested build really creates all generated artifacts.
    pkill -x evaluator_server 2>/dev/null || true
    rm -f evaluator_server evaluator.pb.cc evaluator.pb.h evaluator.grpc.pb.cc evaluator.grpc.pb.h \
          evaluator_pb2.py evaluator_pb2_grpc.py results.log
    rm -rf __pycache__ /tmp/verifier_stubs /tmp/evaluator_safety_test /tmp/evaluator_safety_test.cpp
    timeout 180s make -B all

    test -x "$WORKSPACE/evaluator_server"
    file "$WORKSPACE/evaluator_server" | grep -q 'ELF'
    test -f "$WORKSPACE/evaluator_pb2.py"
    test -f "$WORKSPACE/evaluator_pb2_grpc.py"
    test -f "$WORKSPACE/evaluator.pb.cc"
    test -f "$WORKSPACE/evaluator.grpc.pb.cc"

    # Exercise evaluate_rpn directly under sanitizers so the memory-safety fix
    # cannot be replaced by a hardcoded results.log or server response.
    cat > /tmp/evaluator_safety_test.cpp <<'CPP_EOF'
#include "evaluator.h"
#include <map>
#include <string>
#include <iostream>

static bool expect_ok(const std::string& expr,
                      const std::map<std::string, int>& vars,
                      int expected) {
    try {
        EvalResult r = evaluate_rpn(expr, vars);
        return r.success && r.result == expected;
    } catch (...) {
        return false;
    }
}

static bool expect_error(const std::string& expr) {
    try {
        EvalResult r = evaluate_rpn(expr, {});
        return !r.success && !r.error.empty();
    } catch (...) {
        return false;
    }
}

int main() {
    if (!expect_ok("x 7 + 3 *", {{"x", 5}}, 36)) return 1;
    if (!expect_ok("8 3 - 4 +", {}, 9)) return 2;
    if (!expect_error("+")) return 3;
    if (!expect_error("1 +")) return 4;
    if (!expect_error("")) return 5;
    if (!expect_error("not_a_number")) return 6;
    if (!expect_error("999999999999999999999999999999999")) return 7;
    if (!expect_error("1 1 1 1 1 1 1 1 1 1 1 + + + + + + + + + +")) return 8;
    return 0;
}
CPP_EOF
    g++ -std=c++17 -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all \
        -I"$WORKSPACE" /tmp/evaluator_safety_test.cpp "$WORKSPACE/evaluator.cpp" \
        -o /tmp/evaluator_safety_test
    ASAN_OPTIONS=detect_leaks=0 timeout 20s /tmp/evaluator_safety_test

    # Generate verifier-owned client bindings from the submitted schema.
    mkdir -p /tmp/verifier_stubs
    python3 -m grpc_tools.protoc -I"$WORKSPACE" \
        --python_out=/tmp/verifier_stubs \
        --grpc_python_out=/tmp/verifier_stubs \
        "$WORKSPACE/evaluator.proto"

    "$WORKSPACE/evaluator_server" >/tmp/evaluator_server.log 2>&1 &
    SERVER_PID=$!
    trap 'kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true' EXIT

    # Validate the exact protobuf API and exercise the real gRPC process on
    # independently generated valid and malformed requests.
    PYTHONPATH=/tmp/verifier_stubs timeout 30s python3 - <<'PY_EOF'
import random
import grpc
import evaluator_pb2
import evaluator_pb2_grpc
from google.protobuf.descriptor import FieldDescriptor

fd = evaluator_pb2.DESCRIPTOR
assert fd.package == "build_expr"
assert fd.syntax == "proto3"
assert "Evaluator" in fd.services_by_name
svc = fd.services_by_name["Evaluator"]
assert len(svc.methods) == 1
method = svc.methods[0]
assert method.name == "Evaluate"
assert method.input_type.full_name == "build_expr.EvalRequest"
assert method.output_type.full_name == "build_expr.EvalResponse"

req_desc = fd.message_types_by_name["EvalRequest"]
assert [(f.name, f.number, f.type) for f in req_desc.fields] == [
    ("expression", 1, FieldDescriptor.TYPE_STRING),
    ("variables", 2, FieldDescriptor.TYPE_MESSAGE),
]
assert req_desc.fields_by_name["variables"].message_type.GetOptions().map_entry
key_f, value_f = req_desc.fields_by_name["variables"].message_type.fields
assert key_f.type == FieldDescriptor.TYPE_STRING
assert value_f.type == FieldDescriptor.TYPE_INT32

resp_desc = fd.message_types_by_name["EvalResponse"]
assert [(f.name, f.number, f.type) for f in resp_desc.fields] == [
    ("result", 1, FieldDescriptor.TYPE_INT32),
    ("success", 2, FieldDescriptor.TYPE_BOOL),
    ("error_message", 3, FieldDescriptor.TYPE_STRING),
]

channel = grpc.insecure_channel("localhost:50051")
grpc.channel_ready_future(channel).result(timeout=10)
stub = evaluator_pb2_grpc.EvaluatorStub(channel)

def evaluate(expr, variables=None):
    return stub.Evaluate(
        evaluator_pb2.EvalRequest(expression=expr, variables=variables or {}),
        timeout=3,
    )

rng = random.Random(91427)
for i in range(35):
    variables = {"v": rng.randint(-8, 8)}
    first_is_var = (i % 3 == 0)
    value = variables["v"] if first_is_var else rng.randint(-8, 8)
    tokens = ["v" if first_is_var else str(value)]
    for _ in range(rng.randint(1, 6)):
        operand = rng.randint(-6, 6)
        op = rng.choice(["+", "-", "*"])
        tokens.extend([str(operand), op])
        if op == "+":
            value += operand
        elif op == "-":
            value -= operand
        else:
            value *= operand
    response = evaluate(" ".join(tokens), variables)
    assert response.success, (tokens, response.error_message)
    assert response.result == value, (tokens, response.result, value)
    assert response.error_message == ""

malformed = [
    "+",
    "1 +",
    "1 2",
    "unknown_token",
    "999999999999999999999999999999999",
    "1 1 1 1 1 1 1 1 1 1 1 + + + + + + + + + +",
]
for expr in malformed:
    response = evaluate(expr)
    assert not response.success, expr
    assert response.error_message, expr
    # Confirm malformed input did not terminate the service.
    alive = evaluate("6 4 -")
    assert alive.success and alive.result == 2

channel.close()
PY_EOF

    # The supplied cases must remain intact, and the supplied client must
    # actually communicate with the running service to create results.log.
    python3 - <<'PY_EOF'
import json
path = "/home/user/workspace/test_cases.json"
with open(path) as f:
    actual = json.load(f)
expected = [
  {"expr": "ARCH_ARM64 1 +", "vars": {"ARCH_ARM64": 1}},
  {"expr": "1 2 + 3 *", "vars": {}},
  {"expr": "+", "vars": {}},
  {"expr": "1 1 1 1 1 1 1 1 1 1 1 1 + + + + + + + + + + +", "vars": {}},
]
assert actual == expected
PY_EOF
    timeout 30s python3 "$WORKSPACE/client.py" "$WORKSPACE/test_cases.json" "$WORKSPACE/results.log"

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import re

WORKSPACE_DIR = "/home/user/workspace"
RESULTS_LOG = os.path.join(WORKSPACE_DIR, "results.log")
PROTO_FILE = os.path.join(WORKSPACE_DIR, "evaluator.proto")
MAKEFILE = os.path.join(WORKSPACE_DIR, "Makefile")

def test_results_log_exists():
    assert os.path.isfile(RESULTS_LOG), f"Expected results file {RESULTS_LOG} does not exist. Did the client script run successfully?"

def test_results_log_contents():
    with open(RESULTS_LOG, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 lines in {RESULTS_LOG}, found {len(lines)}. Server might have crashed or test cases were modified."

    # Case 1: ARCH_ARM64 1 +
    assert "ARCH_ARM64 1 +" in lines[0]
    assert "True" in lines[0]
    assert "2" in lines[0].split("|")[2].strip()

    # Case 2: 1 2 + 3 *
    assert "1 2 + 3 *" in lines[1]
    assert "True" in lines[1]
    assert "9" in lines[1].split("|")[2].strip()

    # Case 3: + (Stack underflow)
    assert "+" in lines[2]
    assert "False" in lines[2], "Expected success=False for underflow case."
    assert "RPC FAILED" not in lines[2], "Server crashed on underflow case instead of returning an error safely."

    # Case 4: 1 1 1... + + +... (Stack overflow)
    assert "1 1 1" in lines[3]
    assert "False" in lines[3], "Expected success=False for overflow case."
    assert "RPC FAILED" not in lines[3], "Server crashed on overflow case instead of returning an error safely."

def test_proto_file_exists():
    assert os.path.isfile(PROTO_FILE), f"File {PROTO_FILE} does not exist."
    with open(PROTO_FILE, 'r') as f:
        content = f.read()

    assert "syntax" in content and "proto3" in content, "Proto file must use proto3 syntax."
    assert "package build_expr;" in content or "package build_expr" in content, "Proto file must use package build_expr."
    assert "service Evaluator" in content, "Proto file must define service Evaluator."
    assert "message EvalRequest" in content, "Proto file must define message EvalRequest."
    assert "message EvalResponse" in content, "Proto file must define message EvalResponse."

def test_makefile_exists_and_targets():
    assert os.path.isfile(MAKEFILE), f"File {MAKEFILE} does not exist."
    with open(MAKEFILE, 'r') as f:
        content = f.read()

    assert re.search(r'^all:', content, re.MULTILINE), "Makefile missing 'all' target."
    assert re.search(r'^evaluator_server:', content, re.MULTILINE), "Makefile missing 'evaluator_server' target."
    assert re.search(r'^python_stubs:', content, re.MULTILINE), "Makefile missing 'python_stubs' target."

def test_generated_files_exist():
    assert os.path.isfile(os.path.join(WORKSPACE_DIR, "evaluator_server")), "evaluator_server binary not built."
    assert os.path.isfile(os.path.join(WORKSPACE_DIR, "evaluator_pb2.py")), "evaluator_pb2.py not generated."
    assert os.path.isfile(os.path.join(WORKSPACE_DIR, "evaluator_pb2_grpc.py")), "evaluator_pb2_grpc.py not generated."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
)
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
