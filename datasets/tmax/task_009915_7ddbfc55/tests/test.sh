#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import sys
import tempfile
import time

import pytest

INVESTIGATION_JSON = "/home/user/investigation.json"
SERVICE_DIR = "/home/user/service"
VENV_DIR = os.path.join(SERVICE_DIR, "venv")
REQUIREMENTS = os.path.join(SERVICE_DIR, "requirements.txt")
CORE_DUMP = os.path.join(SERVICE_DIR, "core.dmp")
FUZZER = os.path.join(SERVICE_DIR, "fuzzer.py")


def venv_python():
    for name in ("python", "python3"):
        path = os.path.join(VENV_DIR, "bin", name)
        if os.path.isfile(path):
            return path
    pytest.fail(f"Virtual environment not found or missing python binary at {VENV_DIR}.")


def load_investigation():
    with open(INVESTIGATION_JSON, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{INVESTIGATION_JSON} is not a valid JSON file.")


def test_investigation_json_exists():
    assert os.path.isfile(INVESTIGATION_JSON), f"File {INVESTIGATION_JSON} does not exist."


def test_investigation_json_content():
    data = load_investigation()

    assert "fixed_markup_safe_version" in data, "Missing 'fixed_markup_safe_version' in JSON."
    assert "leaked_secret_key" in data, "Missing 'leaked_secret_key' in JSON."
    assert "deadlock_payload" in data, "Missing 'deadlock_payload' in JSON."

    assert data["leaked_secret_key"] == "SECRET_KEY_BEGIN_ZGVhZGxlYWtfczNjcjN0X2tleV8yMDIz_END", \
        "Incorrect leaked_secret_key extracted from the memory dump."
    assert data["deadlock_payload"] == "HANG_ME", \
        "Incorrect deadlock_payload discovered."

    version = data["fixed_markup_safe_version"]
    assert isinstance(version, str), "fixed_markup_safe_version must be a string."
    assert version.startswith("1."), \
        f"fixed_markup_safe_version should be a 1.x version to resolve the conflict, got {version}."


def test_venv_exists():
    venv_python()


def test_secret_is_present_in_dump():
    data = load_investigation()
    with open(CORE_DUMP, "rb") as f:
        dump = f.read()
    extracted = re.findall(rb"SECRET_KEY_BEGIN_[A-Za-z0-9+/=]+_END", dump)
    assert extracted, "No wrapped secret key was found in core.dmp."
    assert data["leaked_secret_key"].encode() in extracted, \
        "The reported secret key was not extracted from core.dmp."


def test_requirements_fixed_and_installed():
    assert os.path.isfile(REQUIREMENTS), "requirements.txt is missing."
    text = open(REQUIREMENTS, "r").read()
    data = load_investigation()
    version = data["fixed_markup_safe_version"]

    markup = re.search(r"(?im)^\s*MarkupSafe\s*==\s*([^\s#]+)", text)
    flask = re.search(r"(?im)^\s*Flask\s*==\s*([^\s#]+)", text)
    assert markup, "requirements.txt must contain a pinned MarkupSafe dependency."
    assert flask, "requirements.txt must still contain the Flask dependency."
    assert markup.group(1) == version, \
        "The MarkupSafe version in requirements.txt does not match investigation.json."
    assert markup.group(1) != "2.1.2", "The original conflicting MarkupSafe pin was not fixed."

    py = venv_python()
    check = subprocess.run(
        [py, "-m", "pip", "check"], cwd=SERVICE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20
    )
    assert check.returncode == 0, f"The virtual environment has broken dependencies:\n{check.stdout}"

    query = subprocess.run(
        [py, "-c",
         "import importlib.metadata as m; "
         "print(m.version('MarkupSafe')); print(m.version('Flask'))"],
        cwd=SERVICE_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert query.returncode == 0, f"Required packages are not installed in the venv: {query.stderr}"
    installed = query.stdout.strip().splitlines()
    assert len(installed) >= 2
    assert installed[0] == version, \
        f"Installed MarkupSafe version {installed[0]} does not match reported version {version}."
    assert installed[1] == flask.group(1), \
        "Installed Flask version does not match requirements.txt."


def test_app_imports_and_runs_in_venv():
    py = venv_python()
    imported = subprocess.run(
        [py, "-c", "import app; assert callable(app.process_payload)"],
        cwd=SERVICE_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert imported.returncode == 0, f"app.py does not import in the venv:\n{imported.stderr}"

    run = subprocess.run(
        [py, os.path.join(SERVICE_DIR, "app.py")], cwd=SERVICE_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert run.returncode == 0, f"app.py fails when run in the venv:\n{run.stderr}"


def test_reported_payload_really_hangs():
    py = venv_python()
    payload = load_investigation()["deadlock_payload"]
    assert isinstance(payload, str) and 5 <= len(payload) <= 10

    control = subprocess.run(
        [py, "-c", "import app,sys; raise SystemExit(0 if app.process_payload(sys.argv[1]) is True else 1)", "SAFE_INPUT"],
        cwd=SERVICE_DIR, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=5
    )
    assert control.returncode == 0, "process_payload does not return normally for a control input."

    proc = subprocess.Popen(
        [py, "-c", "import app,sys; app.process_payload(sys.argv[1])", payload],
        cwd=SERVICE_DIR, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        time.sleep(2)
        assert proc.poll() is None, "The reported deadlock payload does not cause process_payload to hang."
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)


def test_fuzzer_exists_and_exercises_process_payload():
    assert os.path.isfile(FUZZER), f"Fuzzer not found at {FUZZER}."
    assert os.path.getsize(FUZZER) > 0, "fuzzer.py is empty."

    py = venv_python()
    payload = load_investigation()["deadlock_payload"]
    fd, calls_path = tempfile.mkstemp(prefix="fuzzer_calls_", suffix=".jsonl")
    os.close(fd)
    harness = "/tmp/run_fuzzer_with_probe.py"
    with open(harness, "w") as f:
        f.write(r'''import json
import os
import runpy
import sys

service = "/home/user/service"
sys.path.insert(0, service)
import app
_original = app.process_payload
_log = os.environ["FUZZER_CALL_LOG"]

def observed_process_payload(payload):
    with open(_log, "a") as out:
        out.write(json.dumps(payload) + "\n")
        out.flush()
    return _original(payload)

app.process_payload = observed_process_payload
runpy.run_path("/home/user/service/fuzzer.py", run_name="__main__")
''')

    env = os.environ.copy()
    env["FUZZER_CALL_LOG"] = calls_path
    try:
        result = subprocess.run(
            [py, harness], cwd=SERVICE_DIR, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
    except subprocess.TimeoutExpired:
        pytest.fail("fuzzer.py did not detect and isolate the hanging payload within 30 seconds.")

    assert result.returncode == 0, \
        f"fuzzer.py failed when executed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"

    calls = []
    with open(calls_path, "r") as f:
        for line in f:
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(value, str):
                calls.append(value)
    os.unlink(calls_path)

    assert payload in calls, "fuzzer.py never called process_payload with the discovered payload."
    assert len(set(calls)) >= 2, \
        "fuzzer.py must fuzz process_payload with various inputs, not only the known answer."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
