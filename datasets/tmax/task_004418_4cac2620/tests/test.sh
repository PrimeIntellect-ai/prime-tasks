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
import os
import random
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/alert"
PORT_HEX = format(8080, "04X")


def request_alert(timeout=5):
    try:
        response = requests.get(URL, timeout=timeout)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Failed to connect to the server at {URL}. Is the server running?")
    except requests.exceptions.Timeout:
        pytest.fail(f"Request to {URL} timed out.")
    except Exception as exc:
        pytest.fail(f"An unexpected error occurred while requesting {URL}: {exc}")

    assert response.status_code == 200, (
        f"Expected status code 200, but got {response.status_code}. "
        f"Response body: {response.text}"
    )
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, (
        f"Expected Content-Type to include 'application/json', but got '{content_type}'"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Failed to parse response body as JSON. Response body: {response.text}")


def listening_inodes():
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            if local_address.rsplit(":", 1)[-1].upper() == PORT_HEX and state == "0A":
                result.add(fields[9])
    return result


def listener_pid():
    inodes = listening_inodes()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.name)
        except (OSError, PermissionError):
            continue
    return None


def read_process(pid):
    raw_cmd = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    cmd = [item.decode(errors="surrogateescape") for item in raw_cmd if item]
    assert cmd, "The process listening on port 8080 has no usable command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    for item in Path(f"/proc/{pid}/environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return cmd, cwd, env


def find_server_source(cmd, cwd, env):
    candidates = []
    for arg in cmd[1:]:
        path = Path(arg)
        if not path.is_absolute():
            path = Path(cwd) / path
        if path.is_file() and path.suffix == ".py":
            candidates.append(path)

    flask_app = env.get("FLASK_APP", "").split(":", 1)[0]
    if flask_app:
        path = Path(flask_app)
        if not path.suffix:
            path = path.with_suffix(".py")
        if not path.is_absolute():
            path = Path(cwd) / path
        if path.is_file():
            candidates.append(path)

    if "-m" in cmd:
        index = cmd.index("-m")
        if index + 1 < len(cmd):
            path = Path(cwd) / (cmd[index + 1].replace(".", "/") + ".py")
            if path.is_file():
                candidates.append(path)

    assert candidates, "The running Python server is not backed by an identifiable Python source file"
    return candidates[0].resolve()


def assert_regex_extraction(source_path):
    source = source_path.read_text(errors="replace")
    tree = ast.parse(source, filename=str(source_path))
    regex_names = set()
    imported_re = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(alias.name == "re" for alias in node.names):
                imported_re = True
        elif isinstance(node, ast.ImportFrom) and node.module == "re":
            imported_re = True
            regex_names.update(alias.asname or alias.name for alias in node.names)

    operations = {"search", "match", "fullmatch", "findall", "finditer", "compile"}
    used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr in operations:
            used = True
        elif isinstance(func, ast.Name) and func.id in regex_names:
            used = True

    assert imported_re and used, "The server source does not contain the required regex-based extraction routine"


def stop_original(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 5
    while time.time() < deadline:
        if listener_pid() is None:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    deadline = time.time() + 5
    while time.time() < deadline and listener_pid() is not None:
        time.sleep(0.1)
    assert listener_pid() is None, "Could not stop the original server for pipeline testing"


def start_server(cmd, cwd, env):
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 120
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None and listener_pid() is None:
            pytest.fail(f"The server exited during startup with status {proc.returncode}")
        try:
            response = requests.get(URL, timeout=2)
            if response.status_code == 200:
                return proc
        except Exception as exc:
            last_error = exc
        time.sleep(0.5)
    pytest.fail(f"The server did not become ready after restart: {last_error}")


def stop_started(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_alert_endpoint_and_pipeline():
    # Preserve all original endpoint assertions for the supplied inputs.
    expected_original = {
        "error_code": "E-72",
        "node_name": "omega 9",
        "node_ip": "10.0.0.42",
        "owner": "SRE-Team",
    }
    assert request_alert() == expected_original, "JSON payload does not match expected output"

    pid = listener_pid()
    assert pid is not None, "No process is listening on 127.0.0.1:8080"
    cmd, cwd, env = read_process(pid)
    source_path = find_server_source(cmd, cwd, env)
    assert source_path.is_file(), "The required Python server artifact does not exist"
    assert_regex_extraction(source_path)

    audio_path = Path("/app/alert.wav")
    csv_path = Path("/home/user/nodes.csv")
    original_audio = audio_path.read_bytes()
    original_csv = csv_path.read_bytes()

    letter = random.choice(["A", "B", "C", "D"])
    first_digit = random.choice(["one", "two", "four", "six", "seven", "eight"])
    second_digit = random.choice(["one", "three", "four", "six", "seven", "nine"])
    node_word = random.choice(["alpha", "delta", "omega", "tango"])
    node_digit = random.choice(["one", "two", "three", "six", "eight", "nine"])
    numbers = {
        "one": "1", "two": "2", "three": "3", "four": "4",
        "six": "6", "seven": "7", "eight": "8", "nine": "9",
    }
    node_name = f"{node_word} {numbers[node_digit]}"
    ip = f"172.{random.randint(16, 30)}.{random.randint(1, 250)}.{random.randint(1, 250)}"
    owner = f"Dynamic-Team-{random.randint(10000, 99999)}"
    expected_dynamic = {
        "error_code": f"{letter}-{numbers[first_digit]}{numbers[second_digit]}",
        "node_name": node_name,
        "node_ip": ip,
        "owner": owner,
    }

    proc = None
    stop_original(pid)
    try:
        phrase = (
            f"System alert. Error code {letter} {first_digit} {second_digit}. "
            f"Server node {node_word} {node_digit}."
        )
        subprocess.run(["espeak", "-w", str(audio_path), phrase], check=True)
        csv_path.write_text(
            "node_name,ip_address,owner\n"
            "unused 5,192.0.2.10,Decoy-Team\n"
            f"{node_name},{ip},{owner}\n"
            "unused 8,192.0.2.20,Other-Decoy\n"
        )

        proc = start_server(cmd, cwd, env)
        actual = request_alert(timeout=10)
        assert actual == expected_dynamic, (
            "The server did not transcribe, normalize, and join the dynamically supplied "
            f"audio/CSV inputs. Got: {actual}, expected: {expected_dynamic}"
        )
    finally:
        if proc is not None:
            stop_started(proc)
        audio_path.write_bytes(original_audio)
        csv_path.write_bytes(original_csv)
        # Restore the requested final running state using the agent's own artifact.
        try:
            start_server(cmd, cwd, env)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
