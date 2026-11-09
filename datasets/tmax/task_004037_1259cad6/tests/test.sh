#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import base64
import ctypes
import json
import os
import random
import subprocess
import textwrap
import urllib.error
import urllib.request

SO_PATH = "/home/user/libchecksum.so"
API_URL = "http://127.0.0.1:8080/checksum"
VENV_PYTHON = "/home/user/venv/bin/python"
VENV_PYTEST = "/home/user/venv/bin/pytest"


def expected_checksum(data):
    return sum((i + 1) * value for i, value in enumerate(data))


def load_checksum_library():
    lib = ctypes.CDLL(SO_PATH)
    func = lib.compute_weighted_checksum
    func.argtypes = [ctypes.POINTER(ctypes.c_ubyte), ctypes.c_size_t]
    func.restype = ctypes.c_ulonglong
    return lib, func


def call_c(func, data):
    if not data:
        return func(None, 0)
    array = (ctypes.c_ubyte * len(data)).from_buffer_copy(data)
    return func(array, len(data))


def post_checksum(data):
    encoded = base64.b64encode(data).decode("ascii")
    body = json.dumps({"payload": encoded}).encode("utf-8")
    request = urllib.request.Request(
        API_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status = response.status
            raw_body = response.read().decode("utf-8")
    except urllib.error.URLError as exc:
        raise AssertionError(f"Failed to connect to API or API returned error: {exc}") from exc

    assert status == 200, f"Expected status 200, got {status}"
    try:
        response_json = json.loads(raw_body)
    except json.JSONDecodeError as exc:
        raise AssertionError("API did not return valid JSON.") from exc
    assert "checksum" in response_json, "Response JSON missing 'checksum' key"
    assert isinstance(response_json["checksum"], int) and not isinstance(response_json["checksum"], bool), \
        "Response checksum must be an integer"
    return response_json["checksum"]


def test_shared_library_exists_and_exports():
    """Verify that libchecksum.so exists and exports compute_weighted_checksum."""
    assert os.path.exists("/home/user/checksum.c"), "C source /home/user/checksum.c does not exist."
    assert os.path.isfile(SO_PATH), f"Shared library {SO_PATH} does not exist."

    try:
        lib, _ = load_checksum_library()
    except OSError as exc:
        assert False, f"Failed to load {SO_PATH}: {exc}"

    assert hasattr(lib, "compute_weighted_checksum"), \
        "compute_weighted_checksum function is not exported by the shared library."


def test_shared_library_computes_weighted_checksums():
    """Exercise the exported ABI on edge cases and verifier-generated data."""
    _, func = load_checksum_library()
    cases = [
        b"",
        b"test",
        b"\x00",
        b"\xff",
        bytes(range(256)),
        b"\x00\xff\x00\x80\x01",
        bytes([255]) * 1000,
    ]
    rng = random.SystemRandom()
    for _ in range(40):
        cases.append(os.urandom(rng.randrange(0, 1001)))

    for data in cases:
        actual = call_c(func, data)
        expected = expected_checksum(data)
        assert actual == expected, \
            f"C checksum mismatch for input of length {len(data)}: expected {expected}, got {actual}"


def test_api_running_and_correct():
    """Preserve the original API check for the fixed payload."""
    actual = post_checksum(b"test")
    assert actual == 1127, f"Expected checksum 1127, got {actual}"


def test_api_handles_general_base64_payloads():
    """Exercise Base64 decoding and checksum calculation on unpredictable inputs."""
    cases = [
        b"",
        b"\x00",
        b"\xff",
        b"\x00\xff\x10\x80",
        bytes(range(256)),
        bytes([255]) * 1000,
    ]
    rng = random.SystemRandom()
    for _ in range(35):
        cases.append(os.urandom(rng.randrange(0, 1001)))

    for data in cases:
        actual = post_checksum(data)
        expected = expected_checksum(data)
        assert actual == expected, \
            f"API checksum mismatch for input of length {len(data)}: expected {expected}, got {actual}"


def test_virtualenv_and_property_test_artifact():
    assert os.path.isfile(VENV_PYTHON), "Virtual environment Python is missing."
    assert os.path.isfile(VENV_PYTEST), "pytest is not installed in /home/user/venv."
    import_check = subprocess.run(
        [VENV_PYTHON, "-c", "import flask, pytest, requests, hypothesis"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert import_check.returncode == 0, \
        f"Required packages are not importable from the virtual environment:\n{import_check.stdout}"

    test_path = "/home/user/test_api.py"
    assert os.path.isfile(test_path), f"Property test script {test_path} does not exist."
    source = open(test_path, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=test_path)

    imported_modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_modules.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported_modules.add(node.module)

    assert any(name == "hypothesis" or name.startswith("hypothesis.") for name in imported_modules), \
        "test_api.py must import Hypothesis."
    assert "requests" in imported_modules, "test_api.py must import requests."
    assert "base64" in imported_modules, "test_api.py must Base64-encode generated bytes."

    given_calls = []
    binary_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = node.func.id if isinstance(node.func, ast.Name) else (
            node.func.attr if isinstance(node.func, ast.Attribute) else ""
        )
        if name == "given":
            given_calls.append(node)
        elif name == "binary":
            binary_calls.append(node)

    assert given_calls, "test_api.py must define a Hypothesis @given property test."
    assert binary_calls, "test_api.py must use a Hypothesis binary byte-string strategy."

    valid_binary_range = False
    for call in binary_calls:
        kwargs = {kw.arg: kw.value for kw in call.keywords if kw.arg}
        max_node = kwargs.get("max_size")
        min_node = kwargs.get("min_size")
        max_value = max_node.value if isinstance(max_node, ast.Constant) else None
        min_value = min_node.value if isinstance(min_node, ast.Constant) else 0
        if max_value == 1000 and min_value == 0:
            valid_binary_range = True
            break
    assert valid_binary_range, \
        "Hypothesis binary strategy must generate byte strings with min_size=0 and max_size=1000."
    assert API_URL in source, "test_api.py must send requests to the required checksum endpoint."


def test_execute_property_tests_and_write_log():
    """Run the submitted tests normally and ensure they reject an incorrect API result."""
    log_path = "/home/user/test_results.log"
    normal = subprocess.run(
        [VENV_PYTEST, "/home/user/test_api.py", "-v"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
        cwd="/home/user",
    )
    with open(log_path, "w", encoding="utf-8") as log_file:
        log_file.write(normal.stdout)
    assert normal.returncode == 0, f"Submitted property tests failed:\n{normal.stdout}"

    shim_dir = "/tmp/checksum_negative_control"
    os.makedirs(shim_dir, exist_ok=True)
    trace_path = os.path.join(shim_dir, "requests_seen.log")
    if os.path.exists(trace_path):
        os.unlink(trace_path)

    shim = textwrap.dedent(r'''
        import base64
        import json as _json
        import os
        import requests

        _trace = os.environ.get("CHECKSUM_TRACE")

        class _WrongResponse:
            status_code = 200
            ok = True
            reason = "OK"
            headers = {"Content-Type": "application/json"}

            def __init__(self, checksum):
                self._body = {"checksum": checksum}
                self.text = _json.dumps(self._body)
                self.content = self.text.encode("utf-8")

            def json(self):
                return dict(self._body)

            def raise_for_status(self):
                return None

        def _response(kwargs):
            body = kwargs.get("json")
            if body is None and kwargs.get("data") is not None:
                raw = kwargs.get("data")
                if isinstance(raw, bytes):
                    raw = raw.decode("utf-8")
                body = _json.loads(raw)
            encoded = body.get("payload", "") if isinstance(body, dict) else ""
            data = base64.b64decode(encoded)
            correct = sum((i + 1) * value for i, value in enumerate(data))
            if _trace:
                with open(_trace, "a", encoding="utf-8") as stream:
                    stream.write(str(len(data)) + "\n")
            return _WrongResponse(correct + 1)

        def _post(url, *args, **kwargs):
            return _response(kwargs)

        def _request(method, url, *args, **kwargs):
            return _response(kwargs)

        def _session_post(self, url, *args, **kwargs):
            return _response(kwargs)

        def _session_request(self, method, url, *args, **kwargs):
            return _response(kwargs)

        requests.post = _post
        requests.request = _request
        requests.api.post = _post
        requests.api.request = _request
        requests.sessions.Session.post = _session_post
        requests.sessions.Session.request = _session_request
    ''')
    with open(os.path.join(shim_dir, "sitecustomize.py"), "w", encoding="utf-8") as shim_file:
        shim_file.write(shim)

    env = os.environ.copy()
    env["PYTHONPATH"] = shim_dir + os.pathsep + env.get("PYTHONPATH", "")
    env["CHECKSUM_TRACE"] = trace_path
    negative = subprocess.run(
        [VENV_PYTEST, "/home/user/test_api.py", "-v"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
        cwd="/home/user",
        env=env,
    )
    assert os.path.exists(trace_path) and os.path.getsize(trace_path) > 0, \
        "The submitted property test did not issue a requests-based checksum call."
    assert negative.returncode != 0, \
        "The submitted property test passed even when every API checksum was deliberately incorrect."


def test_test_results_log():
    """Preserve the original assertion that the test log exists and reports passing tests."""
    log_path = "/home/user/test_results.log"
    assert os.path.exists(log_path), f"Test results log {log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as file:
        content = file.read()
    assert "passed" in content.lower(), \
        "Test results log does not indicate that tests passed. Expected 'passed' in log."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
