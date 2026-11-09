#!/bin/bash
set -e
mkdir -p /logs/verifier

# Remove any server the agent may have left running before verification.
pkill -f '/home/user/auth_project/app.py' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import random
import shutil
import signal
import string
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

import pytest

PROJECT_DIR = "/home/user/auth_project"
REQUIREMENTS_FILE = os.path.join(PROJECT_DIR, "requirements.txt")
SHARED_LIB = os.path.join(PROJECT_DIR, "lib/libccrypto.so")
TEST_RESULTS_FILE = os.path.join(PROJECT_DIR, "test_results.json")
BUILD_SCRIPT = os.path.join(PROJECT_DIR, "build_polyglot.py")
APP_SCRIPT = os.path.join(PROJECT_DIR, "app.py")
E2E_SCRIPT = os.path.join(PROJECT_DIR, "test_e2e.py")
DEPS_DIR = "/tmp/verifier_python_deps"


def verifier_env():
    env = os.environ.copy()
    old = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = DEPS_DIR + (os.pathsep + old if old else "")
    env["FLASK_DEBUG"] = "0"
    env["FLASK_ENV"] = "production"
    return env


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=5)
    except Exception:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except Exception:
            pass


def post_hash(password, attempts=50):
    body = json.dumps({"password": password}).encode("utf-8")
    request = urllib.request.Request(
        "http://127.0.0.1:5000/hash",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    last_error = None
    for _ in range(attempts):
        try:
            with urllib.request.urlopen(request, timeout=1) as response:
                assert response.status == 200
                return json.loads(response.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Flask server did not become available: {last_error}")


# Original assertions are retained.
def test_requirements_modified():
    assert os.path.isfile(REQUIREMENTS_FILE), f"Requirements file is missing: {REQUIREMENTS_FILE}"
    with open(REQUIREMENTS_FILE, "r") as f:
        content = f.read()

    conflict_present = "Flask==2.0.0" in content and "Werkzeug==3.0.0" in content
    assert not conflict_present, "requirements.txt still contains the conflicting Flask==2.0.0 and Werkzeug==3.0.0 versions."


def test_shared_library_exists():
    assert os.path.isfile(SHARED_LIB), f"Shared library is missing: {SHARED_LIB}"
    with open(SHARED_LIB, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", f"File {SHARED_LIB} is not a valid ELF shared object."


def test_python_scripts_exist():
    scripts = ["build_polyglot.py", "app.py", "test_e2e.py"]
    for script in scripts:
        script_path = os.path.join(PROJECT_DIR, script)
        assert os.path.isfile(script_path), f"Required script is missing: {script_path}"


def test_results_json():
    assert os.path.isfile(TEST_RESULTS_FILE), f"Test results file is missing: {TEST_RESULTS_FILE}"
    with open(TEST_RESULTS_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {TEST_RESULTS_FILE} does not contain valid JSON.")

    assert "hash" in data, "JSON result is missing the 'hash' key."
    expected_hash = "SECURE_test_password_123"
    assert data["hash"] == expected_hash, f"Expected hash '{expected_hash}', but got '{data['hash']}'"


def test_requirements_are_installable_and_importable():
    shutil.rmtree(DEPS_DIR, ignore_errors=True)
    os.makedirs(DEPS_DIR)
    install = subprocess.run(
        [sys.executable, "-m", "pip", "install", "--disable-pip-version-check", "--target", DEPS_DIR, "-r", REQUIREMENTS_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert install.returncode == 0, f"requirements.txt is not installable:\n{install.stdout}"
    imported = subprocess.run(
        [sys.executable, "-c", "import flask, werkzeug, requests; print(flask.__version__)"],
        env=verifier_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert imported.returncode == 0, f"Installed Flask/Werkzeug combination cannot be imported:\n{imported.stdout}"


def test_scripts_contain_required_orchestration():
    with open(BUILD_SCRIPT, encoding="utf-8") as f:
        build_source = f.read()
    ast.parse(build_source)
    assert "subprocess" in build_source, "build_polyglot.py must use Python subprocess orchestration"
    assert "gcc" in build_source, "build_polyglot.py must invoke gcc"

    with open(APP_SCRIPT, encoding="utf-8") as f:
        app_source = f.read()
    ast.parse(app_source)
    assert "Flask" in app_source, "app.py must implement a Flask application"
    assert "ctypes" in app_source, "app.py must load the C library through ctypes"

    with open(E2E_SCRIPT, encoding="utf-8") as f:
        e2e_source = f.read()
    ast.parse(e2e_source)
    assert "5000" in e2e_source and "/hash" in e2e_source, "test_e2e.py must exercise the port 5000 /hash endpoint"


def test_build_script_really_builds_working_crypto_library():
    if os.path.lexists(SHARED_LIB):
        os.remove(SHARED_LIB)
    run = subprocess.run(
        [sys.executable, BUILD_SCRIPT],
        cwd=PROJECT_DIR,
        env=verifier_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=40,
    )
    assert run.returncode == 0, f"build_polyglot.py failed:\n{run.stdout}"
    assert os.path.isfile(SHARED_LIB), "build_polyglot.py did not create lib/libccrypto.so"
    with open(SHARED_LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    library = ctypes.CDLL(SHARED_LIB)
    function = library.compute_hash
    function.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    function.restype = None
    value = ("probe_" + "".join(random.choice(string.ascii_letters) for _ in range(18))).encode()
    output = ctypes.create_string_buffer(256)
    function(value, output)
    assert output.value == b"SECURE_" + value, "Built library does not expose the required compute_hash behavior"


def test_app_uses_the_shared_library_for_dynamic_inputs():
    # Replace the just-built library temporarily with a verifier-generated one.
    # A Python-hardcoded SECURE_ response cannot pass this check.
    original_library = open(SHARED_LIB, "rb").read()
    prefix = "VERIFY_" + "".join(random.choice(string.ascii_uppercase) for _ in range(16)) + "_"
    source = os.path.join(PROJECT_DIR, "lib", ".verifier_crypto.c")
    with open(source, "w", encoding="utf-8") as f:
        f.write('#include <string.h>\nvoid compute_hash(const char *input, char *output) { strcpy(output, "' + prefix + '"); strcat(output, input); }\n')
    compile_result = subprocess.run(
        ["gcc", "-shared", "-fPIC", source, "-o", SHARED_LIB],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, compile_result.stdout

    proc = None
    try:
        proc = subprocess.Popen(
            [sys.executable, APP_SCRIPT],
            cwd=PROJECT_DIR,
            env=verifier_env(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        for _ in range(3):
            password = "pw_" + "".join(random.choice(string.ascii_letters + string.digits) for _ in range(20))
            response = post_hash(password)
            assert response == {"hash": prefix + password}, f"Unexpected API response: {response}"
    finally:
        stop_process(proc)
        with open(SHARED_LIB, "wb") as f:
            f.write(original_library)
        try:
            os.remove(source)
        except FileNotFoundError:
            pass


def test_e2e_script_executes_server_request_and_cleanup():
    # First execute the submitted pipeline against the real submitted app.
    try:
        os.remove(TEST_RESULTS_FILE)
    except FileNotFoundError:
        pass
    real_run = subprocess.run(
        [sys.executable, E2E_SCRIPT],
        cwd=PROJECT_DIR,
        env=verifier_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=45,
        start_new_session=True,
    )
    assert real_run.returncode == 0, f"test_e2e.py failed:\n{real_run.stdout}"
    assert os.path.isfile(TEST_RESULTS_FILE), "test_e2e.py did not generate test_results.json"
    with open(TEST_RESULTS_FILE, encoding="utf-8") as f:
        genuine_result = json.load(f)
    assert genuine_result == {"hash": "SECURE_test_password_123"}

    # Instrument app.py with a nonce response. This proves test_e2e.py actually
    # starts app.py, POSTs the required payload, records its exact response, and
    # leaves no server process behind.
    original_app = open(APP_SCRIPT, "rb").read()
    original_results = open(TEST_RESULTS_FILE, "rb").read()
    nonce = "E2E_" + "".join(random.choice(string.ascii_letters + string.digits) for _ in range(24))
    marker = "/tmp/verifier_e2e_server_pid"
    try:
        os.remove(marker)
    except FileNotFoundError:
        pass
    wrapper = f'''import json, os\nfrom http.server import BaseHTTPRequestHandler, HTTPServer\nopen({marker!r}, "w").write(str(os.getpid()))\nclass H(BaseHTTPRequestHandler):\n    def log_message(self, *args): pass\n    def do_GET(self):\n        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")\n    def do_POST(self):\n        n = int(self.headers.get("Content-Length", "0")); data = json.loads(self.rfile.read(n))\n        if self.path != "/hash" or data != {{"password": "test_password_123"}}:\n            self.send_response(400); self.end_headers(); return\n        body = json.dumps({{"hash": {nonce!r}}}).encode()\n        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)\nHTTPServer(("127.0.0.1", 5000), H).serve_forever()\n'''
    server_pid = None
    try:
        with open(APP_SCRIPT, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.remove(TEST_RESULTS_FILE)
        run = subprocess.run(
            [sys.executable, E2E_SCRIPT],
            cwd=PROJECT_DIR,
            env=verifier_env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=45,
            start_new_session=True,
        )
        assert run.returncode == 0, f"Instrumented test_e2e.py run failed:\n{run.stdout}"
        assert os.path.isfile(marker), "test_e2e.py did not start app.py"
        server_pid = int(open(marker).read().strip())
        with open(TEST_RESULTS_FILE, encoding="utf-8") as f:
            result = json.load(f)
        assert result == {"hash": nonce}, "test_e2e.py did not save the exact live server response"
        time.sleep(1)
        assert not os.path.exists(f"/proc/{server_pid}"), "test_e2e.py left its background server running"
    finally:
        if server_pid is not None and os.path.exists(f"/proc/{server_pid}"):
            try:
                os.kill(server_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        with open(APP_SCRIPT, "wb") as f:
            f.write(original_app)
        with open(TEST_RESULTS_FILE, "wb") as f:
            f.write(original_results)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
