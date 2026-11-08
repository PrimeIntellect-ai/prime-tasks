#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the image's default server so the verifier can observe the actual
# WebSocket message through a private capture file.
pkill -f '^python3 /home/user/ws_server.py$' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess
import time

import pytest

ARTIFACT = "/home/user/artifact"
SCRIPT = "/home/user/analyze.sh"
REPORT = "/home/user/report.json"
WS_RECEIVED = "/home/user/ws_received.json"


def get_max_glibc(filepath):
    try:
        output = subprocess.check_output(
            ["readelf", "-V", filepath], text=True, stderr=subprocess.DEVNULL
        )
    except Exception:
        return "0.0"

    versions = []
    for line in output.splitlines():
        match = re.search(r"Name:\s*GLIBC_([0-9.]+)", line)
        if match:
            versions.append(match.group(1))

    if not versions:
        return "0.0"
    return max(versions, key=lambda value: tuple(int(x) for x in value.split(".")))


def local_dependencies(filepath):
    output = subprocess.check_output(["readelf", "-d", filepath], text=True)
    needed = re.findall(r"Shared library: \[([^]]+)\]", output)
    return sorted(
        name for name in needed
        if os.path.isfile(os.path.join(ARTIFACT, "lib", name))
    )


def build_fresh_artifacts():
    token = secrets.token_hex(5)
    names = {
        "alpha": f"lib{token}alpha.so",
        "beta": f"lib{token}beta.so",
        "gamma": f"lib{token}gamma.so",
    }
    symbols = {key: f"{token}_{key}_func" for key in names}

    bin_dir = os.path.join(ARTIFACT, "bin")
    lib_dir = os.path.join(ARTIFACT, "lib")
    os.makedirs(bin_dir, exist_ok=True)
    os.makedirs(lib_dir, exist_ok=True)
    for entry in os.listdir(lib_dir):
        path = os.path.join(lib_dir, entry)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

    source_dir = f"/tmp/artifact_sources_{token}"
    os.makedirs(source_dir)
    gamma_c = os.path.join(source_dir, "gamma.c")
    beta_c = os.path.join(source_dir, "beta.c")
    alpha_c = os.path.join(source_dir, "alpha.c")
    server_c = os.path.join(source_dir, "server.c")

    with open(gamma_c, "w") as f:
        f.write(f'#include <stdio.h>\nvoid {symbols["gamma"]}(void) {{ puts("gamma"); }}\n')
    with open(beta_c, "w") as f:
        f.write(f'#include <stdio.h>\nvoid {symbols["beta"]}(void) {{ puts("beta"); }}\n')
    with open(alpha_c, "w") as f:
        f.write(
            f'#include <stdio.h>\nvoid {symbols["gamma"]}(void);\n'
            f'void {symbols["alpha"]}(void) {{ puts("alpha"); {symbols["gamma"]}(); }}\n'
        )
    with open(server_c, "w") as f:
        f.write(
            f'#include <stdio.h>\nvoid {symbols["alpha"]}(void);\n'
            f'void {symbols["beta"]}(void);\n'
            f'int main(void) {{ puts("server"); {symbols["alpha"]}(); {symbols["beta"]}(); return 0; }}\n'
        )

    def run(command):
        subprocess.check_call(command)

    run(["gcc", "-shared", "-fPIC", "-o", os.path.join(lib_dir, names["gamma"]),
         gamma_c, f"-Wl,-soname,{names['gamma']}"])
    run(["gcc", "-shared", "-fPIC", "-o", os.path.join(lib_dir, names["beta"]),
         beta_c, f"-Wl,-soname,{names['beta']}"])
    run(["gcc", "-shared", "-fPIC", "-o", os.path.join(lib_dir, names["alpha"]),
         alpha_c, "-L" + lib_dir, "-Wl,--no-as-needed", f"-l:{names['gamma']}",
         f"-Wl,-soname,{names['alpha']}", "-Wl,-rpath,$ORIGIN"])
    run(["gcc", "-o", os.path.join(bin_dir, "server"), server_c,
         "-L" + lib_dir, "-Wl,--no-as-needed", f"-l:{names['alpha']}",
         f"-l:{names['beta']}", "-Wl,-rpath,$ORIGIN/../lib",
         "-Wl,-rpath-link," + lib_dir])

    expected = {}
    pending = [("server", os.path.join(bin_dir, "server"))]
    visited = set()
    while pending:
        key, path = pending.pop(0)
        if key in visited:
            continue
        visited.add(key)
        deps = local_dependencies(path)
        expected[key] = {
            "dependencies": deps,
            "max_glibc": get_max_glibc(path),
        }
        for dep in deps:
            pending.append((dep, os.path.join(lib_dir, dep)))
    return expected


def start_capture_server(capture_path, ready_path):
    server_path = "/tmp/verifier_ws_server.py"
    with open(server_path, "w") as f:
        f.write(r'''import asyncio
import json
import sys
import websockets

capture_path, ready_path = sys.argv[1:3]

async def handler(websocket, *args):
    message = await websocket.recv()
    with open(capture_path, "w") as out:
        json.dump(message, out)
    with open("/home/user/ws_received.json", "w") as out:
        out.write(message)

async def main():
    async with websockets.serve(handler, "127.0.0.1", 9090):
        with open(ready_path, "w") as out:
            out.write("ready")
        await asyncio.Future()

asyncio.run(main())
''')
    process = subprocess.Popen(
        ["python3", server_path, capture_path, ready_path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    for _ in range(100):
        if os.path.exists(ready_path):
            return process
        if process.poll() is not None:
            error = process.stderr.read()
            pytest.fail(f"Verifier WebSocket server failed to start: {error}")
        time.sleep(0.05)
    process.terminate()
    pytest.fail("Verifier WebSocket server did not become ready.")


@pytest.fixture(scope="session")
def executed_analysis():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    with open(SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace")
    assert first_line.startswith("#!") and "bash" in first_line, "analyze.sh must be a Bash script."

    expected = build_fresh_artifacts()
    capture_path = f"/tmp/ws_capture_{secrets.token_hex(12)}.json"
    ready_path = f"/tmp/ws_ready_{secrets.token_hex(12)}"
    for path in (REPORT, WS_RECEIVED, capture_path, ready_path):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    server = start_capture_server(capture_path, ready_path)
    try:
        result = subprocess.run(
            [SCRIPT], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30
        )
        assert result.returncode == 0, (
            f"analyze.sh exited with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        for _ in range(100):
            if os.path.isfile(capture_path):
                break
            time.sleep(0.05)
        assert os.path.isfile(capture_path), "No WebSocket text message was received from analyze.sh."
        with open(capture_path) as f:
            captured_text = json.load(f)
        return expected, captured_text
    finally:
        server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill()


def test_analyze_script_exists_and_executable(executed_analysis):
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_report_json_exists_and_valid(executed_analysis):
    assert os.path.isfile(REPORT), f"Report file {REPORT} is missing."
    with open(REPORT) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT} does not contain valid JSON.")
    assert isinstance(data, dict), "Report JSON must be an object/dictionary."


def test_ws_received_json_exists_and_matches(executed_analysis):
    assert os.path.isfile(WS_RECEIVED), "WebSocket received file is missing. Did the script send the payload?"
    with open(REPORT) as f:
        report_data = json.load(f)
    with open(WS_RECEIVED) as f:
        try:
            ws_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {WS_RECEIVED} does not contain valid JSON.")
    assert report_data == ws_data, "The WebSocket payload does not match report.json."

    _, captured_text = executed_analysis
    try:
        captured_data = json.loads(captured_text)
    except json.JSONDecodeError:
        pytest.fail("The script's actual WebSocket message was not valid JSON.")
    assert captured_data == report_data, "The actual WebSocket message does not match report.json."


def test_report_json_content(executed_analysis):
    expected, _ = executed_analysis
    with open(REPORT) as f:
        data = json.load(f)

    for key, expected_entry in expected.items():
        assert key in data, f"Missing key '{key}' in report JSON."
        assert "dependencies" in data[key], f"Missing 'dependencies' for '{key}'."
        assert "max_glibc" in data[key], f"Missing 'max_glibc' for '{key}'."

        actual_deps = data[key]["dependencies"]
        expected_deps = expected_entry["dependencies"]
        assert sorted(actual_deps) == sorted(expected_deps), (
            f"Dependencies for '{key}' are incorrect. Expected {expected_deps}, got {actual_deps}."
        )
        assert actual_deps == sorted(actual_deps), f"Dependencies for '{key}' are not alphabetically sorted."

        expected_glibc = expected_entry["max_glibc"]
        actual_glibc = data[key]["max_glibc"]
        if expected_glibc != "0.0":
            assert actual_glibc == expected_glibc, (
                f"max_glibc for '{key}' is incorrect. Expected {expected_glibc}, got {actual_glibc}."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
