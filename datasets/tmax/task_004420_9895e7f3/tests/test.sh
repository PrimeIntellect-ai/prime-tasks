#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import subprocess

import pytest
import pytesseract
import requests
from PIL import Image

BUILD_DIR = "/home/user/build"
PROCESSOR_PATH = f"{BUILD_DIR}/processor.py"
TEST_PATH = f"{BUILD_DIR}/test_processor.py"
DEPLOY_PATH = f"{BUILD_DIR}/deploy.py"
TOKEN_PATH = "/home/user/build_token.txt"
REFERENCE_PATH = "/app/reference.png"
MEMDUMP_PATH = "/app/memdump.raw"


def read_ast(path):
    assert os.path.isfile(path) and not os.path.islink(path), f"Expected a regular file at {path}"
    with open(path, "r", encoding="utf-8") as f:
        return ast.parse(f.read(), filename=path)


def expected_ocr_label():
    assert os.path.isfile(REFERENCE_PATH), f"Reference image {REFERENCE_PATH} is missing"
    return pytesseract.image_to_string(Image.open(REFERENCE_PATH)).strip()


def test_token_file_contents():
    token_path = "/home/user/build_token.txt"
    assert os.path.isfile(token_path), f"Token file {token_path} is missing."
    with open(token_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == "MEM_SEC_0xFA9B", f"Expected token 'MEM_SEC_0xFA9B' in {token_path}, but got '{content}'"


def test_token_was_extracted_from_dump():
    import re

    with open(MEMDUMP_PATH, "rb") as f:
        dump = f.read()
    matches = re.findall(rb"MEM_SEC_[A-Za-z0-9]{6}(?![A-Za-z0-9])", dump)
    assert len(matches) == 1, f"Expected exactly one valid memory token, found {len(matches)}"
    with open(TOKEN_PATH, "rb") as f:
        submitted = f.read().strip()
    assert submitted == matches[0], "build_token.txt does not contain the token extracted from memdump.raw"


def test_http_service_health():
    url = "http://127.0.0.1:8080/health"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP service at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON. Response text: {response.text}")

    expected_data = {"status": "running", "token": "MEM_SEC_0xFA9B"}
    assert data == expected_data, f"Expected JSON {expected_data}, but got {data}"


def listening_pids(port):
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                rows = list(f)[1:]
        except OSError:
            continue
        for row in rows:
            fields = row.split()
            if len(fields) >= 10 and fields[3] == "0A":
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                if local_port == port:
                    socket_inodes.add(fields[9])

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in socket_inodes:
                    pids.add(int(name))
                    break
        except OSError:
            continue
    return pids


def test_service_is_the_requested_deployment_process():
    pids = listening_pids(8080)
    assert pids, "No process is listening on port 8080"
    valid = False
    diagnostics = []
    for pid in pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = [x.decode("utf-8", "replace") for x in f.read().split(b"\0") if x]
            cwd = os.readlink(f"/proc/{pid}/cwd")
        except OSError:
            continue
        diagnostics.append(argv)
        if len(argv) < 2 or not os.path.basename(argv[0]).startswith("python"):
            continue
        script = argv[1] if os.path.isabs(argv[1]) else os.path.join(cwd, argv[1])
        if os.path.realpath(script) == os.path.realpath(DEPLOY_PATH):
            valid = True
            break
    assert valid, f"Port 8080 is not being served by {DEPLOY_PATH}; listener commands: {diagnostics}"


def test_processor_is_the_boundary_repair_and_handles_derived_inputs():
    actual = read_ast(PROCESSOR_PATH)
    expected = ast.parse('''def process_matrix(matrix):
    max_iters = len(matrix)
    i = 0
    while i < max_iters:
        matrix[i] = matrix[i] * 2
        i += 1
    return matrix
''')
    assert ast.dump(actual, include_attributes=False) == ast.dump(expected, include_attributes=False), \
        "processor.py must preserve the original algorithm and repair only the off-by-one loop boundary"

    probe = '''
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("submitted_processor", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
values = json.loads(sys.argv[2])
original_id = id(values)
result = module.process_matrix(values)
print(json.dumps({"same": id(result) == original_id, "result": result}))
'''
    cases = [[], [7], [-5, 0, 11], list(range(-13, 18))]
    for case in cases:
        result = subprocess.run(
            ["python3", "-c", probe, PROCESSOR_PATH, json.dumps(case)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"processor.py failed on {case}:\n{result.stdout}\n{result.stderr}"
        observed = json.loads(result.stdout.strip().splitlines()[-1])
        assert observed["same"] is True, "process_matrix must preserve its in-place behavior"
        assert observed["result"] == [value * 2 for value in case]


def test_processor_tests_pass():
    test_file = "/home/user/build/test_processor.py"
    assert os.path.isfile(test_file), f"Test file {test_file} is missing."

    result = subprocess.run(["pytest", test_file], capture_output=True, text=True)
    assert result.returncode == 0, f"pytest failed for {test_file}. Output:\n{result.stdout}\n{result.stderr}"


def test_processor_test_contains_the_ocr_assertion():
    label = expected_ocr_label()
    assert label, "Tesseract returned an empty label for reference.png"
    actual = read_ast(TEST_PATH)
    expected = ast.parse(f'''from processor import process_matrix
from PIL import Image
import pytesseract

def test_process():
    matrix = [1, 2, 3]
    try:
        process_matrix(matrix)
        result_label = pytesseract.image_to_string(Image.open("/app/reference.png")).strip()
    except IndexError:
        result_label = "FAILED"

    assert result_label == {label!r}
''')
    assert ast.dump(actual, include_attributes=False) == ast.dump(expected, include_attributes=False), \
        "test_processor.py must retain the build test and place the OCR result in its assertion"


def test_deploy_artifact_preserves_the_flask_architecture():
    actual = read_ast(DEPLOY_PATH)
    expected = ast.parse('''from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    token = "UNKNOWN"
    if os.path.exists('/home/user/build_token.txt'):
        with open('/home/user/build_token.txt', 'r') as f:
            token = f.read().strip()
    return jsonify({"status": "running", "token": token})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
''')
    assert ast.dump(actual, include_attributes=False) == ast.dump(expected, include_attributes=False), \
        "deploy.py must remain the requested Flask deployment architecture"

    spec = importlib.util.spec_from_file_location("submitted_deploy", DEPLOY_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    response = module.app.test_client().get("/health")
    assert response.status_code == 200
    with open(TOKEN_PATH, "r", encoding="utf-8") as f:
        token = f.read().strip()
    assert response.get_json() == {"status": "running", "token": token}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
