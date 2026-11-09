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
import io
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import time
import zipfile

import pytest
import requests

APP = "/app"
EXPECTED_DOC1 = "Intro text.\n[GCODE]\nLINEAR_MOVE X:10 Y:20\nG0 Z5\n[/GCODE]\nEnd text."
EXPECTED_DOC2 = "[GCODE]\nLINEAR_MOVE X:50.5 Y:10.2\n[/GCODE]"


def get(url):
    try:
        return requests.get(url, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to {url}: {exc}")


def wait_for(url):
    last = None
    for _ in range(20):
        try:
            response = requests.get(url, timeout=1)
            if response.status_code < 500:
                return response
            last = f"HTTP {response.status_code}"
        except requests.RequestException as exc:
            last = str(exc)
        time.sleep(0.25)
    pytest.fail(f"Service at {url} did not become available: {last}")


def process_cmdlines():
    results = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as handle:
                cmdline = handle.read().replace(b"\0", b" ").decode(errors="replace")
            with open(f"/proc/{name}/status", "r") as handle:
                status = handle.read()
            match = re.search(r"^Uid:\s+(\d+)\s+(\d+)", status, re.MULTILINE)
            effective_uid = int(match.group(2)) if match else None
            results.append((cmdline, effective_uid))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return results


@pytest.fixture(scope="session")
def processed_batch():
    script = "/app/process_docs.py"
    assert os.path.isfile(script), f"{script} is missing or is not a regular file."
    assert not os.path.islink(script), f"{script} must be an actual submitted script, not a symlink."
    with open(script, "rb") as handle:
        compile(handle.read(), script, "exec")

    nonce = secrets.token_hex(8)
    dynamic_name = f"extra_{nonce}.txt"
    escaped_name = f"escaped_{nonce}.txt"
    dynamic_source = (
        f"Batch {nonce}\n"
        "G1 X999 Y888\n"
        "[GCODE]\n"
        "G1 X73.25 Y4.125\n"
        "G0 Z9\n"
        "[/GCODE]\n"
        f"Tail {nonce}.\n"
    )
    dynamic_expected = (
        f"Batch {nonce}\n"
        "G1 X999 Y888\n"
        "[GCODE]\n"
        "LINEAR_MOVE X:73.25 Y:4.125\n"
        "G0 Z9\n"
        "[/GCODE]\n"
        f"Tail {nonce}."
    )

    zip_bytes = io.BytesIO()
    with zipfile.ZipFile(zip_bytes, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("doc1.txt", "Intro text.\n[GCODE]\nG1 X10 Y20\nG0 Z5\n[/GCODE]\nEnd text.\n")
        archive.writestr("doc2.txt", "[GCODE]\nG1 X50.5 Y10.2\n[/GCODE]\n")
        archive.writestr(dynamic_name, dynamic_source)
        archive.writestr("../system_config.txt", "MALICIOUS OVERWRITE\n")
        archive.writestr(f"../{escaped_name}", "ESCAPED\n")

    tar_path = "/app/incoming/docs.tar"
    replacement = tar_path + ".verifier"
    with tarfile.open(replacement, "w") as archive:
        info = tarfile.TarInfo("payload.zip")
        payload = zip_bytes.getvalue()
        info.size = len(payload)
        archive.addfile(info, io.BytesIO(payload))
    os.replace(replacement, tar_path)

    shutil.rmtree("/app/extracted", ignore_errors=True)
    os.makedirs("/app/extracted", exist_ok=True)
    escaped_path = os.path.join("/app", escaped_name)
    if os.path.lexists(escaped_path):
        os.remove(escaped_path)

    result = subprocess.run(
        ["python3", script], cwd="/app", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, f"process_docs.py failed:\n{result.stdout}"

    assert not os.path.exists(escaped_path), "Zip Slip entry escaped /app/extracted/."
    with open("/app/system_config.txt", "r") as handle:
        assert handle.read().strip() == "SAFE_ORIGINAL_CONFIG", \
            "system_config.txt was overwritten! Zip Slip vulnerability was not properly mitigated."

    for filename in ("doc1.txt", "doc2.txt", dynamic_name):
        path = os.path.join("/app/extracted", filename)
        assert os.path.isfile(path), f"process_docs.py did not extract {filename}."

    return dynamic_name, dynamic_expected


def test_system_config_not_overwritten():
    """Verify that the Zip Slip attack was mitigated and system_config.txt is intact."""
    config_path = "/app/system_config.txt"
    assert os.path.isfile(config_path), f"{config_path} is missing."
    with open(config_path, "r") as f:
        content = f.read().strip()
    assert content == "SAFE_ORIGINAL_CONFIG", "system_config.txt was overwritten! Zip Slip vulnerability was not properly mitigated."


def test_nginx_flask_doc1(processed_batch):
    """Verify doc1.txt is served correctly with transformed GCODE."""
    url = "http://127.0.0.1:8080/docs/doc1.txt"
    response = wait_for(url)
    assert response.status_code == 200, f"Expected HTTP 200 for {url}, got {response.status_code}"
    actual_content = response.text.strip()
    assert EXPECTED_DOC1 in actual_content or actual_content == EXPECTED_DOC1, \
        f"Transformed content for doc1.txt is incorrect.\nExpected:\n{EXPECTED_DOC1}\nGot:\n{actual_content}"


def test_nginx_flask_doc2(processed_batch):
    """Verify doc2.txt is served correctly with transformed GCODE."""
    url = "http://127.0.0.1:8080/docs/doc2.txt"
    response = get(url)
    assert response.status_code == 200, f"Expected HTTP 200 for {url}, got {response.status_code}"
    actual_content = response.text.strip()
    assert EXPECTED_DOC2 in actual_content or actual_content == EXPECTED_DOC2, \
        f"Transformed content for doc2.txt is incorrect.\nExpected:\n{EXPECTED_DOC2}\nGot:\n{actual_content}"


def test_random_extracted_file_is_transformed_and_served(processed_batch):
    dynamic_name, dynamic_expected = processed_batch
    extracted = os.path.join("/app/extracted", dynamic_name)
    with open(extracted, "r") as handle:
        assert handle.read().strip() == dynamic_expected

    direct = get(f"http://127.0.0.1:5000/docs/{dynamic_name}")
    proxied = get(f"http://127.0.0.1:8080/docs/{dynamic_name}")
    assert direct.status_code == 200
    assert proxied.status_code == 200
    assert direct.text.strip() == dynamic_expected
    assert proxied.text.strip() == dynamic_expected
    assert "nginx" in proxied.headers.get("Server", "").lower(), \
        "Port 8080 response was not served through Nginx."


def test_nginx_configuration_and_processes(processed_batch):
    result = subprocess.run(
        ["nginx", "-T", "-c", "/app/nginx.conf"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert result.returncode == 0, f"Invalid Nginx configuration:\n{result.stdout}"
    config = re.sub(r"#.*", "", result.stdout)
    assert re.search(r"\blisten\s+(?:127\.0\.0\.1:)?8080\s*;", config), \
        "Nginx is not configured to listen on port 8080."
    locations = re.findall(r"location\s+(?:\^~\s+)?/docs/\s*\{([^}]*)\}", config, re.DOTALL)
    assert locations, "Nginx has no /docs/ location."
    assert any(re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000(?:/)?\s*;", block)
               for block in locations), \
        "The Nginx /docs/ location does not proxy to Flask on 127.0.0.1:5000."

    processes = process_cmdlines()
    nginx_processes = [(cmd, uid) for cmd, uid in processes if "nginx" in cmd.lower()]
    assert nginx_processes, "No running Nginx process was found."
    assert any(uid not in (None, 0) for _, uid in nginx_processes), \
        "Nginx has no non-root worker/process."
    assert any("python" in cmd.lower() and "/app/app.py" in cmd for cmd, _ in processes), \
        "The Flask application /app/app.py is not running."
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
