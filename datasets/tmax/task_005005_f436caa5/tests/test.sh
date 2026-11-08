#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import signal
import string
import subprocess
import time

import pytest

BASE = "/home/user/build_pipeline"
LIB = os.path.join(BASE, "libtelemetry.so")
MAIN = os.path.join(BASE, "main.py")
FINAL = os.path.join(BASE, "final_output.json")


def test_libtelemetry_built():
    assert os.path.exists(LIB), "libtelemetry.so was not built."
    assert os.path.isfile(LIB), "libtelemetry.so is not a regular file."
    library = ctypes.CDLL(LIB)
    assert hasattr(library, "process_telemetry"), "libtelemetry.so does not export process_telemetry."


def test_main_import_order():
    main_path = MAIN
    assert os.path.exists(main_path), "main.py is missing."
    with open(main_path, "r") as f:
        content = f.read()

    config_idx = content.find("import config")
    ffi_idx = content.find("import ffi_wrapper")

    assert config_idx != -1, "main.py is missing 'import config'"
    assert ffi_idx != -1, "main.py is missing 'import ffi_wrapper'"
    assert config_idx < ffi_idx, "config must be imported before ffi_wrapper in main.py to fix the import order bug."


def test_final_output_json():
    filepath = FINAL
    assert os.path.exists(filepath), "final_output.json does not exist."

    with open(filepath, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("final_output.json does not contain valid JSON.")

    assert isinstance(data, dict), "final_output.json should contain a JSON object."
    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    assert data.get("code") == 0, f"Expected code 0, got {data.get('code')}"


def clean_env():
    env = os.environ.copy()
    env.pop("PIPELINE_INIT", None)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def stop_existing_servers():
    subprocess.run(["pkill", "-f", "[m]ain.py"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)


def stop_server(proc):
    if proc is None:
        return
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=3)


def start_server():
    proc = subprocess.Popen(
        ["python3", MAIN], cwd=BASE, env=clean_env(),
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        start_new_session=True,
    )
    for _ in range(40):
        if proc.poll() is not None:
            error = proc.stderr.read().decode(errors="replace")
            pytest.fail(f"main.py failed to start with PIPELINE_INIT unset: {error}")
        result = subprocess.run(
            ["curl", "-fsS", "--max-time", "1", "http://127.0.0.1:8000/telemetry"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            return proc, result.stdout
        time.sleep(0.1)
    stop_server(proc)
    pytest.fail("REST API did not become available on port 8000.")


def test_ffi_and_rest_api_really_use_shared_library():
    stop_existing_servers()

    nonce = ''.join(random.SystemRandom().choice(string.ascii_letters + string.digits) for _ in range(24))
    probe_code = random.SystemRandom().randint(1000, 9999)
    marker = f"/tmp/telemetry_called_{nonce}"
    expected = {"status": f"probe-{nonce}", "code": probe_code}
    backup = f"/tmp/libtelemetry.backup.{nonce}.so"
    probe_c = f"/tmp/telemetry_probe_{nonce}.c"
    probe_so = f"/tmp/libtelemetry_probe_{nonce}.so"
    server = None

    with open(probe_c, "w") as f:
        f.write(f'''#include <stdio.h>\n#include <string.h>\nvoid process_telemetry(const char* input, char* output) {{\n    FILE *m = fopen("{marker}", "w");\n    if (m) {{ fputs("called", m); fclose(m); }}\n    if (strcmp(input, "BUILD_OK") == 0)\n        strcpy(output, "{{\\\"status\\\":\\\"probe-{nonce}\\\",\\\"code\\\":{probe_code}}}");\n    else\n        strcpy(output, "{{\\\"status\\\":\\\"wrong-input\\\",\\\"code\\\":-1}}");\n}}\n''')

    shutil.copy2(LIB, backup)
    try:
        subprocess.run(["gcc", "-shared", "-fPIC", "-o", probe_so, probe_c], check=True)
        os.replace(probe_so, LIB)

        if os.path.exists(marker):
            os.unlink(marker)
        direct = subprocess.run(
            ["python3", "-c", "import config, ffi_wrapper, json; print(json.dumps(ffi_wrapper.get_telemetry()))"],
            cwd=BASE, env=clean_env(), text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, check=False,
        )
        assert direct.returncode == 0, f"get_telemetry() failed: {direct.stderr}"
        assert json.loads(direct.stdout) == expected, "get_telemetry() did not return data produced by the C library."
        assert os.path.exists(marker), "process_telemetry() was not called by get_telemetry()."

        os.unlink(marker)
        server, response = start_server()
        assert json.loads(response) == expected, "The /telemetry endpoint did not return data from get_telemetry()."
        assert os.path.exists(marker), "The REST request did not invoke the C process_telemetry() function."
    finally:
        stop_server(server)
        server = None
        if os.path.exists(backup):
            shutil.copy2(backup, LIB)
        for path in (backup, probe_c, probe_so, marker):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

    stop_existing_servers()
    try:
        server, response = start_server()
        with open(FINAL, "r") as f:
            saved = json.load(f)
        assert json.loads(response) == saved, "final_output.json does not match the response from the repaired REST API."
    finally:
        stop_server(server)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
