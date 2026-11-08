#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import socket
import urllib.request
import urllib.error
import subprocess
import ctypes
import random
import secrets
import runpy
import pytest

PROJECT_DIR = "/home/user/project"

def test_processor_cpp_fixed():
    filepath = os.path.join(PROJECT_DIR, "processor.cpp")
    assert os.path.isfile(filepath), f"{filepath} does not exist"

    with open(filepath, "r") as f:
        content = f.read()

    assert 'extern "C"' in content, "processor.cpp is missing 'extern \"C\"' linkage"
    assert "std::string sort_items" not in content, "processor.cpp should not return std::string directly"

def test_shared_library_compiled():
    so_path = os.path.join(PROJECT_DIR, "libprocessor.so")
    assert os.path.isfile(so_path), f"Shared library {so_path} was not compiled"

def test_server_py_fixed():
    filepath = os.path.join(PROJECT_DIR, "server.py")
    assert os.path.isfile(filepath), f"{filepath} does not exist"

    with open(filepath, "r") as f:
        content = f.read()

    # Keep the original source-level assertion.
    lines = content.split('\n')
    restype_configured = any('lib.sort_items.restype' in line and not line.strip().startswith('#') for line in lines)
    assert restype_configured, "server.py is missing the proper restype configuration for lib.sort_items"

    # Execute the wrapper configuration and verify the actual ctypes type.
    check = subprocess.run(
        ["python3", "-c",
         "import ctypes,runpy; n=runpy.run_path('server.py',run_name='verifier_import'); "
         "assert n['lib'].sort_items.restype is ctypes.c_char_p"],
        cwd=PROJECT_DIR, capture_output=True, text=True, timeout=10
    )
    assert check.returncode == 0, f"server.py does not configure sort_items.restype as ctypes.c_char_p: {check.stderr}"

def test_test_endpoint_sh_exists():
    filepath = os.path.join(PROJECT_DIR, "test_endpoint.sh")
    assert os.path.isfile(filepath), f"{filepath} does not exist"

def test_execute_test_endpoint_script():
    output = os.path.join(PROJECT_DIR, "final_output.json")
    if os.path.exists(output):
        os.unlink(output)
    result = subprocess.run(
        ["bash", os.path.join(PROJECT_DIR, "test_endpoint.sh")],
        cwd=PROJECT_DIR, capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, f"test_endpoint.sh failed: {result.stderr}"
    assert os.path.isfile(output), "test_endpoint.sh did not create final_output.json"

def test_final_output_json():
    filepath = os.path.join(PROJECT_DIR, "final_output.json")
    assert os.path.isfile(filepath), f"{filepath} does not exist"

    with open(filepath, "r") as f:
        content = f.read().strip()

    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail("final_output.json does not contain valid JSON")

    expected = [{"id": 1, "val": "A"}, {"id": 2, "val": "B"}, {"id": 3, "val": "C"}]
    assert data == expected, f"final_output.json content is incorrect. Got: {content}"

def post_json(port, items):
    payload = json.dumps(items).encode("utf-8")
    req = urllib.request.Request(f"http://127.0.0.1:{port}", data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("Content-Length", str(len(payload)))
    with urllib.request.urlopen(req, timeout=4) as response:
        assert response.status == 200, f"Expected HTTP 200 from port {port}, got {response.status}"
        return json.loads(response.read().decode("utf-8"))

def test_reverse_proxy_and_server_running():
    # Keep the original fixed behavioral assertion.
    payload = b'[{"id": 3, "val": "C"}, {"id": 1, "val": "A"}, {"id": 2, "val": "B"}]'
    req = urllib.request.Request("http://127.0.0.1:8000", data=payload, method="POST")
    req.add_header('Content-Length', str(len(payload)))

    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            resp_data = response.read().decode('utf-8')
            try:
                parsed_resp = json.loads(resp_data)
                expected = [{"id": 1, "val": "A"}, {"id": 2, "val": "B"}, {"id": 3, "val": "C"}]
                assert parsed_resp == expected, "Reverse proxy server did not return the correctly sorted JSON"
            except json.JSONDecodeError:
                pytest.fail("Server did not return valid JSON")
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to reverse proxy on port 8000 or server on port 8080: {e}")
    except socket.timeout:
        pytest.fail("Request to port 8000 timed out")

def test_randomized_parsing_sorting_and_forwarding():
    # Answers are derived at verification time, so a fixed-response server cannot pass.
    for count in (4, 7):
        ids = random.sample(range(10, 1000), count)
        items = [{"id": item_id, "val": "v_" + secrets.token_hex(5)} for item_id in ids]
        random.shuffle(items)
        expected = sorted(items, key=lambda item: item["id"])
        direct = post_json(8080, items)
        proxied = post_json(8000, items)
        assert direct == expected, f"Server did not parse and sort randomized input: {direct}"
        assert proxied == expected, f"Proxy endpoint did not parse and sort randomized input: {proxied}"
        assert proxied == direct, "Port 8000 did not produce the same result as the server on port 8080"

def test_socat_proxy_process_running():
    commands = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                commands.append(f.read().replace(b'\0', b' ').decode('utf-8', 'ignore'))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert any('socat' in cmd and '8000' in cmd and '8080' in cmd and '127.0.0.1' in cmd for cmd in commands), \
        "No running socat process forwarding port 8000 to 127.0.0.1:8080 was found"

def test_make_and_shared_library_behavior():
    build = subprocess.run(["make", "-B"], cwd=PROJECT_DIR, capture_output=True, text=True, timeout=30)
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"

    so_path = os.path.join(PROJECT_DIR, "libprocessor.so")
    assert os.path.isfile(so_path), f"Shared library {so_path} was not compiled"
    lib = ctypes.CDLL(so_path)
    func = lib.sort_items
    func.argtypes = [ctypes.c_char_p]
    func.restype = ctypes.c_char_p

    ids = random.sample(range(1000, 9000), 6)
    items = [{"id": item_id, "val": "lib_" + secrets.token_hex(4)} for item_id in ids]
    random.shuffle(items)
    result = func(json.dumps(items).encode("utf-8"))
    assert result is not None, "sort_items returned a null pointer"
    parsed = json.loads(result.decode("utf-8"))
    assert parsed == sorted(items, key=lambda item: item["id"]), \
        "The compiled C++ sort_items function did not parse and sort randomized input"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
