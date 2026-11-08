#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import secrets
import urllib.parse
import urllib.request

WORKSPACE = "/home/user/workspace"
INBOX = os.path.join(WORKSPACE, "inbox")
ORGANIZED = os.path.join(WORKSPACE, "organized")


def request_organize(prefix, expression, destination):
    query = urllib.parse.urlencode({
        "prefix": prefix,
        "expr": expression,
        "dest": destination,
    })
    url = "http://127.0.0.1:8080/organize?" + query
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return response.getcode(), response.read().decode("utf-8")
    except Exception as exc:
        assert False, f"Failed to connect to the server or server returned an error: {exc}"


def assert_successful_move(prefix, result, expression, destination, expected_content=None):
    filename = f"{prefix}{result}.dat"
    source = os.path.join(INBOX, filename)
    target = os.path.join(ORGANIZED, destination, filename)

    assert os.path.isfile(source), f"Test source file is missing before request: {source}"
    status_code, body = request_organize(prefix, expression, destination)
    assert status_code == 200, f"Expected HTTP status 200, got {status_code}"

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        assert False, f"Response body is not valid JSON: {body}"

    expected_data = {
        "status": "success",
        "file": filename,
        "destination": destination,
    }
    assert data == expected_data, f"Expected JSON response {expected_data}, got {data}"
    assert os.path.isfile(target), f"Expected file to be moved to {target}, but it is not there."
    assert not os.path.exists(source), f"Expected file {source} to be removed from inbox, but it still exists."
    if expected_content is not None:
        with open(target, "r") as handle:
            assert handle.read() == expected_content


def test_libexpr_so_exists_and_evaluates_dynamic_expressions():
    library_path = os.path.join(WORKSPACE, "libexpr.so")
    assert os.path.isfile(library_path), "/home/user/workspace/libexpr.so does not exist. Did you compile the C library?"

    try:
        library = ctypes.CDLL(library_path)
        evaluator = library.evaluate_math
    except Exception as exc:
        assert False, f"libexpr.so is not a loadable shared library exposing evaluate_math: {exc}"

    evaluator.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
    evaluator.restype = ctypes.c_int
    rng = secrets.SystemRandom()

    for _ in range(8):
        left = rng.randint(20, 5000)
        right = rng.randint(1, 19)
        operator = rng.choice(["+", "-"])
        expected = left + right if operator == "+" else left - right
        output = ctypes.c_int()
        rc = evaluator(f"{left}{operator}{right}".encode("ascii"), ctypes.byref(output))
        assert rc == 0, f"evaluate_math rejected a valid expression: {left}{operator}{right}"
        assert output.value == expected, f"evaluate_math returned {output.value}, expected {expected}"

    output = ctypes.c_int()
    assert evaluator(b"4*3", ctypes.byref(output)) == -1, "evaluate_math should reject unsupported expressions"


def test_server_py_exists_and_uses_ctypes():
    server_path = os.path.join(WORKSPACE, "server.py")
    assert os.path.isfile(server_path), "/home/user/workspace/server.py does not exist."

    with open(server_path, "r", encoding="utf-8") as handle:
        source = handle.read()
    try:
        tree = ast.parse(source, filename=server_path)
    except SyntaxError as exc:
        assert False, f"server.py is not valid Python: {exc}"

    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == "ctypes" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "ctypes")
        for node in ast.walk(tree)
    )
    loader_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        function = node.func
        if isinstance(function, ast.Name) and function.id in {"CDLL", "PyDLL", "LoadLibrary"}:
            loader_call = True
        elif isinstance(function, ast.Attribute) and function.attr in {"CDLL", "PyDLL", "LoadLibrary"}:
            loader_call = True

    assert imports_ctypes, "server.py must import ctypes"
    assert loader_call, "server.py must load libexpr.so through ctypes"
    assert "evaluate_math" in source, "server.py must call the evaluate_math ABI"


def test_status_ready():
    status_file = "/home/user/workspace/status.txt"
    assert os.path.isfile(status_file), f"{status_file} does not exist. Did you write READY to it?"
    with open(status_file, "r") as f:
        content = f.read().strip()
    assert content == "READY", f"Expected 'READY' in {status_file}, got '{content}'"


def test_web_server_logic():
    # Preserve the original fixed behavioral assertion.
    url = "http://127.0.0.1:8080/organize?prefix=dataset_&expr=3%2B4&dest=reports"

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            status_code = response.getcode()
            body = response.read().decode('utf-8')
    except Exception as e:
        assert False, f"Failed to connect to the server or server returned an error: {e}"

    assert status_code == 200, f"Expected HTTP status 200, got {status_code}"

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        assert False, f"Response body is not valid JSON: {body}"

    expected_data = {"status": "success", "file": "dataset_7.dat", "destination": "reports"}
    assert data == expected_data, f"Expected JSON response {expected_data}, got {data}"

    organized_file = "/home/user/workspace/organized/reports/dataset_7.dat"
    inbox_file = "/home/user/workspace/inbox/dataset_7.dat"
    assert os.path.isfile(organized_file), f"Expected file to be moved to {organized_file}, but it is not there."
    assert not os.path.exists(inbox_file), f"Expected file {inbox_file} to be removed from inbox, but it still exists."


def test_dynamic_expression_and_destination_routing():
    rng = secrets.SystemRandom()
    results = rng.sample([number for number in range(1, 11) if number != 7], 5)

    for result in results:
        left = rng.randint(100, 10000)
        right = left - result
        expression = f"{left}-{right}"
        assert left - right == result
        destination = "audit_" + secrets.token_hex(6)
        assert_successful_move(
            "dataset_",
            result,
            expression,
            destination,
            expected_content=f"data {result}\n",
        )


def test_dynamic_prefix_routing():
    rng = secrets.SystemRandom()
    result = rng.randint(20, 200)
    left = rng.randint(result + 100, result + 10000)
    right = left - result
    expression = f"{left}-{right}"
    assert left - right == result

    prefix = "probe_" + secrets.token_hex(5) + "_"
    destination = "prefix_" + secrets.token_hex(5)
    filename = f"{prefix}{result}.dat"
    content = "routing probe " + secrets.token_hex(12) + "\n"
    with open(os.path.join(INBOX, filename), "w") as handle:
        handle.write(content)

    assert_successful_move(prefix, result, expression, destination, expected_content=content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
