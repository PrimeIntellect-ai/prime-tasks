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
import shutil
import signal
import subprocess
import time
from pathlib import Path

import pytest
import requests
from PIL import Image, ImageDraw, ImageFont

SERVER_URL = "http://127.0.0.1:8080/api/v1/translations"
AUTH_HEADER = {"Authorization": "Bearer loc-agent-2024"}


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            if int(local_address.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                inodes.add(fields[9])

    for proc_dir in Path("/proc").glob("[0-9]*"):
        fd_dir = proc_dir / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc_dir.name)
        except OSError:
            continue
    return None


def test_server_running_and_unauthorized_without_header():
    """Test that the server is running and requires authorization."""
    try:
        response = requests.get(SERVER_URL, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not running on 127.0.0.1:8080 or refused the connection.")

    assert response.status_code == 401, f"Expected 401 Unauthorized when no Authorization header is provided, got {response.status_code}."


def test_server_unauthorized_with_bad_header():
    """Test that the server rejects invalid authorization headers."""
    bad_headers = {"Authorization": "Bearer invalid-token"}
    response = requests.get(SERVER_URL, headers=bad_headers, timeout=5)
    assert response.status_code == 401, f"Expected 401 Unauthorized for invalid token, got {response.status_code}."


def test_server_returns_correct_json_with_valid_auth():
    """Test that the server returns the correctly filtered and decoded translations."""
    response = requests.get(SERVER_URL, headers=AUTH_HEADER, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK for valid token, got {response.status_code}. Body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Body: {response.text}")

    assert "translations" in data, "JSON response must contain a 'translations' key."
    translations = data["translations"]
    assert isinstance(translations, dict), "'translations' must be a JSON object."

    expected_translations = {
        "msg_welcome": "Welcome back, {user}!",
        "msg_french": "Bonjour {user}, le café coûte 5€."
    }
    assert translations == expected_translations, f"Expected translations {expected_translations}, but got {translations}. Check decoding and filtering logic."


def test_rust_pipeline_reloads_changed_ocr_and_cp1252_inputs():
    """Restart the submitted Rust artifact against a second derived fixture."""
    pid = listener_pid()
    assert pid is not None, "Could not identify the process listening on port 8080."

    exe_link = Path(f"/proc/{pid}/exe")
    cwd_link = Path(f"/proc/{pid}/cwd")
    try:
        original_cwd = os.readlink(cwd_link)
        executable_bytes = exe_link.read_bytes()
    except OSError as exc:
        pytest.fail(f"Could not inspect the submitted server executable: {exc}")

    assert executable_bytes.startswith(b"\x7fELF"), "The listening server is not a compiled application."
    rust_markers = (b"rust_begin_unwind", b"rust_eh_personality", b"/rustc/", b"library/std/src")
    assert any(marker in executable_bytes for marker in rust_markers), "The listening server executable does not appear to be a Rust application."

    restart_exe = Path("/tmp/loc_pipeline_submission_bin")
    restart_exe.write_bytes(executable_bytes)
    restart_exe.chmod(0o755)

    image_path = Path("/app/ui_spec.png")
    locale_path = Path("/app/raw_locales.bin")
    original_image = image_path.read_bytes()
    original_locales = locale_path.read_bytes()

    max_len = 24
    required_token = "{client}"
    rows = [
        ("dynamic_cp1252", "Olá {client}, custa 9€."),
        ("dynamic_ascii", "Ready, {client}!"),
        ("wrong_token", "Olá {user}!"),
        ("too_long", "{client} " + "X" * 40),
    ]
    raw_fixture = "\n".join(f"{key}={value}" for key, value in rows).encode("cp1252")

    # Derive the expected result from the generated legacy bytes and constraints.
    decoded = raw_fixture.decode("cp1252")
    expected = {}
    for line in decoded.splitlines():
        key, value = line.split("=", 1)
        if len(value) <= max_len and required_token in value:
            expected[key] = value

    proc = None
    try:
        try:
            font = ImageFont.truetype("DejaVuSansMono.ttf", 30)
        except OSError:
            font = ImageFont.load_default()
        image = Image.new("RGB", (760, 150), "white")
        draw = ImageDraw.Draw(image)
        draw.text((15, 15), f"MAX_LEN: {max_len}\nREQUIRED_TOKEN: {required_token}", fill="black", font=font, spacing=14)
        image.save(image_path)
        locale_path.write_bytes(raw_fixture)

        os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 5
        while time.time() < deadline and listener_pid() is not None:
            time.sleep(0.1)
        if listener_pid() is not None:
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.5)
        assert listener_pid() is None, "The original submitted server could not be stopped for pipeline retesting."

        proc = subprocess.Popen(
            [str(restart_exe)],
            cwd=original_cwd if os.path.isdir(original_cwd) else "/tmp",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        response = None
        deadline = time.time() + 20
        while time.time() < deadline:
            if proc.poll() is not None:
                pytest.fail(f"The submitted Rust server exited during restart with code {proc.returncode}.")
            try:
                response = requests.get(SERVER_URL, headers=AUTH_HEADER, timeout=1)
                break
            except requests.RequestException:
                time.sleep(0.2)
        assert response is not None, "The submitted server did not restart on 127.0.0.1:8080."

        unauthorized = requests.get(SERVER_URL, timeout=5)
        assert unauthorized.status_code == 401, "The restarted server stopped enforcing authorization."
        assert response.status_code == 200, f"Expected 200 after restart, got {response.status_code}: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Restarted server response is not valid JSON: {response.text}")
        assert "translations" in data, "Restarted response lacks the 'translations' key."
        assert isinstance(data["translations"], dict), "Restarted response 'translations' value is not an object."
        assert data["translations"] == expected, (
            f"Changed OCR/CP1252 fixture should produce {expected}, but got {data['translations']}. "
            "The server must extract the changed image constraints, decode CP1252, and filter dynamically."
        )
    finally:
        image_path.write_bytes(original_image)
        locale_path.write_bytes(original_locales)
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
