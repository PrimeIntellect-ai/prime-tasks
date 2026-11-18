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
import secrets
import subprocess
import time

import pytest
import requests

SRC = "/home/user/docs/src"
OUT = "/home/user/docs/out"


def wait_for_file(path, expected, timeout=7):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(path, "r") as f:
                if f.read() == expected:
                    return
        except (FileNotFoundError, OSError):
            pass
        time.sleep(0.2)
    pytest.fail(f"Timed out waiting for transformed file {path}")


def process_running(script_path):
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = f.read().split(b"\0")
            if script_path.encode() in args:
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return False


def test_01_document_transformation_and_serving():
    src_file = "/home/user/docs/src/draft_release_notes.md"
    expected_endpoint = "http://127.0.0.1:8080/pub_release_notes.html"

    # Write the test file to trigger the watcher
    content = "Release %%STATUS%% on %%DATE%%"
    with open(src_file, "w") as f:
        f.write(content)

    # Wait for the watcher to detect and transformer to process
    time.sleep(3)

    # Make HTTP request to the server
    try:
        response = requests.get(expected_endpoint, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP server on 127.0.0.1:8080. Is it running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. File might not have been processed or renamed correctly."

    actual_content = response.text.strip()
    expected_content = "Release PUBLISHED on 2024"

    assert actual_content == expected_content, f"Content mismatch. Expected '{expected_content}', but got '{actual_content}'."


def test_02_transformer_handles_dynamic_bulk_inputs():
    transformer = "/app/transformer.sh"
    assert os.path.isfile(transformer), "/app/transformer.sh is missing"
    assert os.access(transformer, os.X_OK), "/app/transformer.sh is not executable"

    token = secrets.token_hex(12)
    cases = {
        f"draft_{token}.md": f"pub_{token}.html",
        f"notes_{token}.txt": f"notes_{token}.txt",
        f"draft_{token}.txt": f"draft_{token}.txt",
    }

    contents = {
        f"draft_{token}.md": f"{token} %%STATUS%% / %%DATE%% / %%STATUS%% end",
        f"notes_{token}.txt": f"plain-{token}:%%DATE%%:%%STATUS%%",
        f"draft_{token}.txt": f"keep-name-{token}-%%STATUS%%-%%DATE%%",
    }

    for src_name, out_name in cases.items():
        for path in (os.path.join(SRC, src_name), os.path.join(OUT, out_name)):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        with open(os.path.join(SRC, src_name), "w") as f:
            f.write(contents[src_name])

    subprocess.run(["bash", transformer], check=True, timeout=10)

    for src_name, out_name in cases.items():
        out_path = os.path.join(OUT, out_name)
        expected = contents[src_name].replace("%%STATUS%%", "PUBLISHED").replace("%%DATE%%", "2024")
        assert os.path.isfile(out_path), f"Transformer did not generate {out_name}"
        with open(out_path, "r") as f:
            assert f.read() == expected, f"Incorrect transformed content in {out_name}"

    assert not os.path.exists(os.path.join(OUT, f"draft_{token}.md")), "Renamed markdown file was also left under its draft name"

    response = requests.get(f"http://127.0.0.1:8080/pub_{token}.html", timeout=5)
    assert response.status_code == 200
    expected_http = contents[f"draft_{token}.md"].replace("%%STATUS%%", "PUBLISHED").replace("%%DATE%%", "2024")
    assert response.text == expected_http


def test_03_services_and_watcher_process_new_dynamic_file():
    assert process_running("/app/watcher.py"), "/app/watcher.py is not running"
    assert process_running("/app/server.py"), "/app/server.py is not running"

    token = secrets.token_hex(12)
    src_path = os.path.join(SRC, f"draft_watch_{token}.md")
    out_path = os.path.join(OUT, f"pub_watch_{token}.html")
    content = f"watch-{token}-%%STATUS%%-%%DATE%%"
    expected = f"watch-{token}-PUBLISHED-2024"

    for path in (src_path, out_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    with open(src_path, "w") as f:
        f.write(content)

    wait_for_file(out_path, expected)

    response = requests.get(f"http://127.0.0.1:8080/pub_watch_{token}.html", timeout=5)
    assert response.status_code == 200
    assert response.text == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
