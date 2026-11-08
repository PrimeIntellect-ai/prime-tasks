#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import importlib
import json
import os
import random
import re
import secrets
import signal
import subprocess
import sys
import tempfile
import time

BASE_DIR = "/home/user/polyrunner"


def load_translator():
    if BASE_DIR not in sys.path:
        sys.path.insert(0, BASE_DIR)
    try:
        return importlib.import_module("translator")
    except ImportError:
        assert False, "Could not import translator.py"


def run_translation(translator, content, target, expected_output):
    with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".polybuild") as src:
        src.write(content)
        src_path = src.name
    output_path = None
    try:
        actual_target, code = translator.translate(src_path)
        assert actual_target == target, f"Expected target '{target}', got '{actual_target}'"
        suffix = ".py" if target == "python" else ".sh"
        command = ["python3"] if target == "python" else ["bash"]
        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=suffix) as output_file:
            output_file.write(code)
            output_path = output_file.name
        result = subprocess.run(command + [output_path], capture_output=True, text=True, check=True, timeout=10)
        assert result.stdout.strip() == expected_output
    finally:
        if output_path and os.path.exists(output_path):
            os.remove(output_path)
        os.remove(src_path)


def stop_servers():
    victims = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [x.decode(errors="ignore") for x in f.read().split(b"\0") if x]
            cwd = os.path.realpath(f"/proc/{entry}/cwd")
        except (OSError, PermissionError):
            continue
        if "/home/user/polyrunner/server.py" in args or ("server.py" in args and cwd == BASE_DIR):
            victims.append(int(entry))
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.2)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_files_exist():
    assert os.path.isdir(BASE_DIR), f"Directory {BASE_DIR} does not exist."
    for name in ["translator.py", "server.py", "ci_setup.sh"]:
        path = os.path.join(BASE_DIR, name)
        assert os.path.isfile(path), f"File {path} is missing."


def test_translator_python():
    translator = load_translator()
    content = """TARGET python
BEGIN_PSEUDO
PRINT "Initializing python build"
SET_VAR retries 3
PRINT retries
END_PSEUDO
"""
    run_translation(translator, content, "python", "Initializing python build\n3")


def test_translator_bash():
    translator = load_translator()
    content = """TARGET bash
BEGIN_PSEUDO
PRINT "Initializing bash build"
SET_VAR debug_level 5
PRINT debug_level
END_PSEUDO
"""
    run_translation(translator, content, "bash", "Initializing bash build\n5")


def test_translator_on_generated_programs():
    translator = load_translator()
    for target in ("python", "bash"):
        for _ in range(5):
            token = secrets.token_hex(8)
            first_name = "value_" + secrets.token_hex(4)
            second_name = "count_" + secrets.token_hex(4)
            first_value = random.randint(1000, 900000)
            second_value = random.randint(1000, 900000)
            content = (
                f"TARGET {target}\n"
                "BEGIN_PSEUDO\n"
                f"PRINT \"build_{token}\"\n"
                f"SET_VAR {first_name} {first_value}\n"
                f"PRINT {first_name}\n"
                f"SET_VAR {second_name} {second_value}\n"
                f"PRINT {second_name}\n"
                "END_PSEUDO\n"
            )
            expected = f"build_{token}\n{first_value}\n{second_value}"
            run_translation(translator, content, target, expected)


def test_server_and_ci_setup_contents():
    server_path = os.path.join(BASE_DIR, "server.py")
    with open(server_path, "r") as f:
        server_code = f.read()
    assert "9333" in server_code, "server.py does not seem to bind to port 9333."
    assert "websockets" in server_code or "asyncio" in server_code, "server.py does not seem to use websockets/asyncio."

    ci_path = os.path.join(BASE_DIR, "ci_setup.sh")
    with open(ci_path, "r") as f:
        ci_code = f.read()
    assert "pip" in ci_code and "websockets" in ci_code, "ci_setup.sh does not appear to install websockets."
    assert "server.py" in ci_code, "ci_setup.sh does not appear to start server.py."
    assert "sleep 2" in ci_code or "sleep" in ci_code, "ci_setup.sh does not appear to wait for the server to bind."


async def websocket_request(payload):
    import websockets
    deadline = time.monotonic() + 5
    last_error = None
    while time.monotonic() < deadline:
        try:
            async with websockets.connect("ws://localhost:9333", open_timeout=2) as ws:
                await ws.send(json.dumps(payload))
                return json.loads(await asyncio.wait_for(ws.recv(), timeout=8))
        except Exception as exc:
            last_error = exc
            await asyncio.sleep(0.15)
    raise AssertionError(f"Could not communicate with WebSocket server: {last_error}")


def test_ci_script_and_live_websocket_server():
    stop_servers()
    ci_path = os.path.join(BASE_DIR, "ci_setup.sh")
    trace = tempfile.NamedTemporaryFile(mode="w+", delete=False)
    trace_path = trace.name
    trace.close()
    generated_files = []
    try:
        started = time.monotonic()
        with open(trace_path, "w") as trace_output:
            result = subprocess.run(
                ["bash", "-x", ci_path],
                cwd=BASE_DIR,
                stdout=subprocess.DEVNULL,
                stderr=trace_output,
                timeout=45,
            )
        elapsed = time.monotonic() - started
        assert result.returncode == 0, f"ci_setup.sh exited with {result.returncode}"
        assert elapsed >= 1.8, "ci_setup.sh did not wait approximately two seconds"

        with open(trace_path, "r", errors="replace") as f:
            shell_trace = f.read()
        pip_command = re.compile(
            r"(?m)^\++\s+(?:(?:sudo)\s+)?(?:(?:\S*/)?pip(?:3(?:\.\d+)?)?|(?:\S*/)?python(?:3(?:\.\d+)?)?\s+-m\s+pip)\s+install\b[^\n]*websockets"
        )
        sleep_command = re.compile(r"(?m)^\++\s+(?:\S*/)?sleep\s+2(?:\.0+)?s?\s*$")
        assert pip_command.search(shell_trace), "ci_setup.sh did not execute a pip install command for websockets"
        assert sleep_command.search(shell_trace), "ci_setup.sh did not execute a two-second sleep"

        async def exercise_server():
            for target in ("python", "bash"):
                token = secrets.token_hex(10)
                var_name = "job_" + secrets.token_hex(4)
                value = random.randint(10000, 999999)
                content = (
                    f"TARGET {target}\n"
                    "BEGIN_PSEUDO\n"
                    f"PRINT \"socket_{token}\"\n"
                    f"SET_VAR {var_name} {value}\n"
                    f"PRINT {var_name}\n"
                    "END_PSEUDO\n"
                )
                source = tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".polybuild")
                source.write(content)
                source.close()
                generated_files.append(source.name)
                response = await websocket_request({"action": "build", "file": source.name})
                assert response == {
                    "status": "success",
                    "output": f"socket_{token}\n{value}",
                }, f"Unexpected WebSocket response: {response}"

        asyncio.run(exercise_server())
    finally:
        for path in generated_files:
            if os.path.exists(path):
                os.remove(path)
        if os.path.exists(trace_path):
            os.remove(trace_path)
        stop_servers()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
