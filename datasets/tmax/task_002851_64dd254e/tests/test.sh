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
import os
import re
import signal
import subprocess
import tempfile
import time
import uuid

import pytest
import requests

RELEASES_DIR = "/home/user/app/releases/v2"
CURRENT_LINK = "/home/user/app/current"
CONFIG_FILE = "/home/user/app/current/config.txt"
SOURCE_PATH = "/home/user/app/current/server.c"
BINARY_PATH = "/home/user/app/current/server"
SETUP_PATH = "/home/user/setup.sh"
ORIGINAL_CONFIG = "IMAGE=/app/target_image.png\n"


def assert_layout():
    assert os.path.isdir(RELEASES_DIR), f"Directory {RELEASES_DIR} does not exist."
    assert os.path.islink(CURRENT_LINK), f"{CURRENT_LINK} is not a symlink."
    assert os.readlink(CURRENT_LINK) == RELEASES_DIR, f"{CURRENT_LINK} does not point to {RELEASES_DIR}."
    assert os.path.isfile(CONFIG_FILE), f"Config file {CONFIG_FILE} does not exist."
    with open(CONFIG_FILE, "r") as f:
        content = f.read().strip()
    assert content == "IMAGE=/app/target_image.png", f"Config file content is incorrect: {content}"


def listening_socket_inodes(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def socket_owners(inodes):
    owners = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.setdefault(int(pid), set()).add(match.group(1))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def process_args(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [part.decode(errors="replace") for part in f.read().split(b"\0") if part]
    except OSError:
        return []


def assert_real_ssh_tunnel():
    inodes = listening_socket_inodes(9090)
    assert inodes, "Nothing is listening on local port 9090."
    owners = socket_owners(inodes)
    assert owners, "Could not identify the process listening on port 9090."

    ssh_owners = []
    non_ssh_owners = []
    for pid in owners:
        args = process_args(pid)
        executable = os.path.basename(args[0]) if args else ""
        compact = "".join(args)
        has_forward = any(arg == "-L" or arg.startswith("-L") for arg in args)
        is_requested_forward = "9090:127.0.0.1:8080" in compact
        if executable == "ssh" and has_forward and is_requested_forward:
            ssh_owners.append(pid)
        else:
            non_ssh_owners.append((pid, args))

    assert ssh_owners, "Port 9090 is not owned by an ssh process with a local forward to 127.0.0.1:8080."
    assert not non_ssh_owners, f"Port 9090 also has a non-tunnel listener: {non_ssh_owners}"


def kill_port_listeners(port):
    owners = socket_owners(listening_socket_inodes(port))
    for pid in owners:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listening_socket_inodes(port) and time.time() < deadline:
        time.sleep(0.05)
    if listening_socket_inodes(port):
        for pid in socket_owners(listening_socket_inodes(port)):
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        time.sleep(0.2)
    assert not listening_socket_inodes(port), f"Could not stop the existing listener on port {port}."


def wait_for_url(url, timeout=6):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return requests.get(url, timeout=1)
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"Service did not become ready at {url}: {last_error}")


def test_directory_structure_and_config():
    """Verify the directory structure and configuration file exist."""
    assert_layout()


def test_setup_script_exists_and_is_idempotent():
    assert os.path.isfile(SETUP_PATH), f"Setup script {SETUP_PATH} does not exist."
    with open(SETUP_PATH, "rb") as f:
        first_line = f.readline()
    assert b"bash" in first_line, "setup.sh is not a bash script."

    for run_number in (1, 2):
        result = subprocess.run(
            ["/bin/bash", SETUP_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, \
            f"setup.sh failed on idempotency run {run_number}: {result.stderr}"
        assert_layout()


def test_c_server_binary_exists():
    """Verify the C server was compiled."""
    assert os.path.isfile(BINARY_PATH), f"C server binary {BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"C server binary {BINARY_PATH} is not executable."


def test_c_source_exists_and_binary_is_compiled():
    assert os.path.isfile(SOURCE_PATH), f"C source file {SOURCE_PATH} does not exist."
    assert not os.path.islink(SOURCE_PATH), "server.c must be a source file, not a symlink."
    assert os.path.getsize(SOURCE_PATH) > 0, "server.c is empty."

    with open(BINARY_PATH, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", "server is not a compiled ELF executable."

    with tempfile.TemporaryDirectory() as tmpdir:
        obj = os.path.join(tmpdir, "server.o")
        result = subprocess.run(
            ["gcc", "-c", SOURCE_PATH, "-o", obj],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"server.c does not compile as C: {result.stderr}"
        assert os.path.isfile(obj) and os.path.getsize(obj) > 0


def test_http_service_and_tunnel():
    """Verify the HTTP service is accessible via the SSH tunnel and returns correct OCR data."""
    image_path = "/app/target_image.png"
    assert os.path.isfile(image_path), f"Target image {image_path} is missing."

    result = subprocess.run(["tesseract", image_path, "stdout"], capture_output=True, text=True)
    expected_text = result.stdout.strip()

    url = "http://127.0.0.1:9090/extract"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    actual_text = response.text.strip()
    assert expected_text in actual_text or "CONFIDENTIAL-KEY-8842-OMEGA" in actual_text, \
        f"Expected OCR text not found in response. Got: {actual_text}"


def test_http_service_404():
    """Verify the HTTP service returns 404 for unknown endpoints."""
    url = "http://127.0.0.1:9090/unknown_endpoint"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {url}: {e}")
    assert response.status_code == 404, f"Expected status code 404 for unknown endpoint, got {response.status_code}"


def test_listener_is_ssh_tunnel():
    assert_real_ssh_tunnel()


def test_submitted_binary_uses_config_and_tesseract_on_8080():
    token = "VERIFY" + uuid.uuid4().hex[:12].upper()
    image_path = f"/tmp/{token}.png"
    convert = subprocess.run(
        ["convert", "-size", "900x120", "xc:white", "-font", "DejaVu-Sans",
         "-pointsize", "42", "-fill", "black", "-draw", f"text 15,75 '{token}'", image_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert convert.returncode == 0 and os.path.isfile(image_path), f"Failed to make test image: {convert.stderr}"
    expected = subprocess.run(
        ["tesseract", image_path, "stdout"], capture_output=True, text=True, timeout=20, check=True
    ).stdout.strip()
    assert expected, "Tesseract produced no text for the verifier-generated image."

    server_process = None
    try:
        with open(CONFIG_FILE, "w") as f:
            f.write(f"IMAGE={image_path}\n")

        kill_port_listeners(8080)
        server_process = subprocess.Popen(
            [BINARY_PATH],
            cwd=os.path.dirname(BINARY_PATH),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        direct = wait_for_url("http://127.0.0.1:8080/extract")
        assert direct.status_code == 200
        assert direct.text.strip() == expected, \
            f"Direct service did not return tesseract output for the generated image: {direct.text!r}"
        assert direct.headers.get("Content-Type", "").lower().startswith("text/plain"), \
            "The /extract response is not plain text."

        unknown = requests.get("http://127.0.0.1:8080/runtime_probe_unknown", timeout=5)
        assert unknown.status_code == 404

        assert_real_ssh_tunnel()
        tunneled = requests.get("http://127.0.0.1:9090/extract", timeout=5)
        assert tunneled.status_code == 200
        assert tunneled.text.strip() == expected, \
            "Port 9090 did not forward to the submitted server running on port 8080."
    finally:
        with open(CONFIG_FILE, "w") as f:
            f.write(ORIGINAL_CONFIG)
        try:
            kill_port_listeners(8080)
        except Exception:
            if server_process is not None and server_process.poll() is None:
                server_process.kill()
        subprocess.Popen(
            [BINARY_PATH],
            cwd=os.path.dirname(BINARY_PATH),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            os.unlink(image_path)
        except FileNotFoundError:
            pass


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
