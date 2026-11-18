#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import ast
import datetime
import json
import locale
import os
import secrets
import stat
import subprocess
import sys

import pytest

try:
    import zoneinfo
except ImportError:
    from backports import zoneinfo


def test_auth_endpoint_extracted():
    endpoint_path = "/home/user/config/auth_endpoint.txt"
    assert os.path.isfile(endpoint_path), f"File {endpoint_path} does not exist."

    with open(endpoint_path, "r") as f:
        content = f.read().strip()

    assert content == "192.168.100.45:8081", f"Expected '192.168.100.45:8081' in {endpoint_path}, but got '{content}'."


def test_services_json_modified():
    json_path = "/home/user/config/services.json"
    assert os.path.isfile(json_path), f"File {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    api_gateway_deps = data.get("services", {}).get("api-gateway", {}).get("depends_on", [])
    assert "auth-service" in api_gateway_deps, "The 'auth-service' was not added to the 'depends_on' array for 'api-gateway'."


def test_gateway_startup_log():
    log_path = "/home/user/logs/gateway_startup.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. Did the Python script run successfully?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    # Recompute the expected localized time string
    try:
        locale.setlocale(locale.LC_TIME, 'de_DE.UTF-8')
    except locale.Error:
        pytest.fail("Locale de_DE.UTF-8 is not available on the system.")

    dt = datetime.datetime.fromtimestamp(1716388800, tz=zoneinfo.ZoneInfo("Europe/Berlin"))
    expected_time_str = dt.strftime('%A, %d. %B %Y %H:%M:%S')

    expected_log_entry = f"Gateway ready. Auth upstream: 192.168.100.45:8081. Local startup time: {expected_time_str}"

    assert content == expected_log_entry, f"Expected log entry:\n'{expected_log_entry}'\nBut got:\n'{content}'"


def test_gateway_script_implementation_and_execution():
    script_path = "/home/user/api_gateway.py"
    endpoint_path = "/home/user/config/auth_endpoint.txt"
    log_path = "/home/user/logs/gateway_startup.log"

    assert os.path.exists(script_path), f"File {script_path} does not exist."
    assert stat.S_ISREG(os.lstat(script_path).st_mode), f"{script_path} must be a regular Python source file."

    with open(script_path, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=script_path)
    except SyntaxError as exc:
        pytest.fail(f"{script_path} is not valid Python: {exc}")

    imported_modules = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_modules.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported_modules.add(node.module.split('.')[0])

    assert "locale" in imported_modules, "Gateway script must use Python's locale module."
    assert imported_modules.intersection({"zoneinfo", "pytz"}), "Gateway script must use zoneinfo or pytz."

    string_constants = {
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    assert "de_DE.UTF-8" in string_constants, "Gateway script must explicitly select de_DE.UTF-8."
    assert "Europe/Berlin" in string_constants, "Gateway script must explicitly select Europe/Berlin."
    assert "%A, %d. %B %Y %H:%M:%S" in string_constants, "Gateway script must use the required time format."

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    call_names = {
        node.func.attr if isinstance(node.func, ast.Attribute)
        else node.func.id if isinstance(node.func, ast.Name)
        else ""
        for node in calls
    }
    assert "setlocale" in call_names, "Gateway script must configure the locale with locale.setlocale."
    assert "strftime" in call_names, "Gateway script must format the localized datetime with strftime."
    assert any(isinstance(node, ast.With) for node in ast.walk(tree)) or "read_text" in call_names, \
        "Gateway script must read files using a context manager or pathlib.read_text."

    with open(endpoint_path, "rb") as f:
        original_endpoint = f.read()
    original_log_exists = os.path.exists(log_path)
    original_log = None
    if original_log_exists:
        with open(log_path, "rb") as f:
            original_log = f.read()

    dynamic_endpoint = f"10.{secrets.randbelow(200) + 1}.{secrets.randbelow(254) + 1}.{secrets.randbelow(254) + 1}:{secrets.randbelow(40000) + 20000}"

    try:
        with open(endpoint_path, "w", encoding="utf-8") as f:
            f.write(dynamic_endpoint + "\n")
        if os.path.lexists(log_path):
            os.unlink(log_path)

        env = os.environ.copy()
        env.update({"LC_ALL": "C", "LANG": "C", "TZ": "UTC"})
        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Gateway script exited with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(log_path), "Running the gateway script did not create gateway_startup.log."

        locale.setlocale(locale.LC_TIME, "de_DE.UTF-8")
        dt = datetime.datetime.fromtimestamp(1716388800, tz=zoneinfo.ZoneInfo("Europe/Berlin"))
        expected_time = dt.strftime("%A, %d. %B %Y %H:%M:%S")
        expected = f"Gateway ready. Auth upstream: {dynamic_endpoint}. Local startup time: {expected_time}"
        with open(log_path, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        assert actual == expected, f"Executed gateway produced:\n'{actual}'\nExpected:\n'{expected}'"
    finally:
        with open(endpoint_path, "wb") as f:
            f.write(original_endpoint)
        if original_log_exists:
            with open(log_path, "wb") as f:
                f.write(original_log)
        elif os.path.lexists(log_path):
            os.unlink(log_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
