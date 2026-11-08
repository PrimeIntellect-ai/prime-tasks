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
import glob
import os
import signal
import socket
import subprocess
import tarfile
import time
import uuid

import pytest
import requests


def wait_for_server(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


@pytest.fixture(scope="session", autouse=True)
def ensure_server_running():
    server_up = wait_for_server("http://127.0.0.1:8080/")
    # We don't assert here, we let the individual tests fail if the server is down.


def test_intro_route():
    """Verify the /intro route serves the modified intro.txt."""
    url = "http://127.0.0.1:8080/intro"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {url}: {e}")

    assert response.status_code == 200, f"Expected status 200 for /intro, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("text/plain")
    content = response.text
    assert "[INTERNAL DRAFT]" in content[:20], "Response did not start with [INTERNAL DRAFT]"
    assert "Welcome to the v2.0 documentation. This v2.0 system is deprecated." in content, \
        f"Expected modified text in response, got: {content}"


def test_api_route():
    """Verify the /api route serves the modified api.txt."""
    url = "http://127.0.0.1:8080/api"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {url}: {e}")

    assert response.status_code == 200, f"Expected status 200 for /api, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("text/plain")
    content = response.text
    assert "[INTERNAL DRAFT]" in content[:20], "Response did not start with [INTERNAL DRAFT]"
    assert "API v2.0 reference guide." in content, \
        f"Expected modified text in response, got: {content}"


def test_architecture_route():
    """Verify the /architecture route serves the OCR output."""
    url = "http://127.0.0.1:8080/architecture"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {url}: {e}")

    assert response.status_code == 200, f"Expected status 200 for /architecture, got {response.status_code}"
    assert response.headers.get("Content-Type", "").lower().startswith("text/plain")
    content = response.text
    assert "[INTERNAL DRAFT]" in content[:20], "Response did not start with [INTERNAL DRAFT]"
    assert "SYSTEM_ARCHITECTURE_SECRET_8842" in content, \
        f"Expected OCR text in response, got: {content}"


def test_404_route():
    """Verify that an unknown route returns 404."""
    url = "http://127.0.0.1:8080/not_found"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {url}: {e}")

    assert response.status_code == 404, f"Expected status 404 for unknown route, got {response.status_code}"


def test_files_exist_and_modified():
    """Verify that the files exist on disk and were modified correctly."""
    assert os.path.isdir("/app/docs"), "/app/docs directory is missing."

    intro_path = "/app/docs/intro.txt"
    assert os.path.isfile(intro_path), f"{intro_path} is missing."
    with open(intro_path, "r") as f:
        content = f.read()
        assert content.startswith("[INTERNAL DRAFT]\n"), f"{intro_path} does not start with [INTERNAL DRAFT]\\n"
        assert "v2.0" in content and "v1.0" not in content, f"{intro_path} was not updated to v2.0 correctly."

    api_path = "/app/docs/api.txt"
    assert os.path.isfile(api_path), f"{api_path} is missing."
    with open(api_path, "r") as f:
        content = f.read()
        assert content.startswith("[INTERNAL DRAFT]\n"), f"{api_path} does not start with [INTERNAL DRAFT]\\n"
        assert "v2.0" in content and "v1.0" not in content, f"{api_path} was not updated to v2.0 correctly."

    diagram_path = "/app/docs/diagram.txt"
    assert os.path.isfile(diagram_path), f"{diagram_path} is missing."
    with open(diagram_path, "r") as f:
        content = f.read()
        assert content.startswith("[INTERNAL DRAFT]\n"), f"{diagram_path} does not start with [INTERNAL DRAFT]\\n"
        assert "SYSTEM_ARCHITECTURE_SECRET_8842" in content, f"{diagram_path} does not contain OCR text."


def test_every_archived_text_file_was_extracted_and_transformed():
    with tarfile.open("/app/docs.tar.gz", "r:gz") as archive:
        members = [m for m in archive.getmembers() if m.isfile() and m.name.endswith(".txt")]
        assert members, "The archive contains no text files."
        for member in members:
            original = archive.extractfile(member).read()
            expected = b"[INTERNAL DRAFT]\n" + original.replace(b"v1.0", b"v2.0")
            relative = os.path.normpath(member.name).lstrip("./")
            output = os.path.join("/app/docs", relative)
            assert os.path.isfile(output), f"Archived text file was not extracted: {output}"
            with open(output, "rb") as f:
                actual = f.read()
            assert actual == expected, f"{output} was not transformed exactly as required"


def listener_pid_and_executable():
    inode = None
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local, state = fields[1], fields[3]
            if local.upper() == "0100007F:1F90" and state == "0A":
                inode = fields[9]
                break
    assert inode is not None, "No process is listening on 127.0.0.1:8080"

    for proc in glob.glob("/proc/[0-9]*"):
        pid = int(proc.rsplit("/", 1)[1])
        for fd in glob.glob(proc + "/fd/*"):
            try:
                if os.readlink(fd) == f"socket:[{inode}]":
                    return pid, os.path.realpath(proc + "/exe")
            except OSError:
                pass
    pytest.fail("Could not identify the process listening on 127.0.0.1:8080")


def test_listener_is_a_compiled_cpp_server():
    pid, executable = listener_pid_and_executable()
    assert os.path.isfile(executable), "The listening server has no executable file"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The listening server is not a compiled native executable"

    sources = glob.glob("/app/**/*.cpp", recursive=True) + glob.glob("/app/**/*.cc", recursive=True) + glob.glob("/app/**/*.cxx", recursive=True)
    assert sources, "No C++ server source file was found under /app"
    plausible = False
    for source in sources:
        try:
            text = open(source, "r", errors="ignore").read()
            if ("route_config.txt" in text or "8080" in text) and "HTTP" in text.upper():
                plausible = True
                break
        except OSError:
            pass
    assert plausible, "No C++ source under /app appears to implement the requested HTTP server"

    linkage = subprocess.run(["ldd", executable], text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=5).stdout
    if "libstdc++" not in linkage:
        strings = subprocess.run(["strings", executable], text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, timeout=5).stdout
        assert any(marker in strings for marker in ("GLIBCXX_", "CXXABI_", "__gxx_personality")), \
            "The listening executable has no evidence of being compiled as C++"


def test_server_uses_configuration_and_mapped_file_contents():
    pid, executable = listener_pid_and_executable()
    proc_dir = f"/proc/{pid}"
    with open(proc_dir + "/cmdline", "rb") as f:
        argv = [part.decode(errors="surrogateescape") for part in f.read().split(b"\0") if part]
    assert argv, "Could not recover the server command line"
    cwd = os.path.realpath(proc_dir + "/cwd")

    token = uuid.uuid4().hex
    route = "/verify_" + token
    mapped_path = "/app/docs/verify_" + token + ".txt"
    expected = ("dynamic mapped content " + token + "\n").encode()
    config_path = "/app/route_config.txt"
    with open(config_path, "rb") as f:
        original_config = f.read()

    replacement = None
    try:
        with open(mapped_path, "wb") as f:
            f.write(expected)
        with open(config_path, "wb") as f:
            f.write(original_config)
            if original_config and not original_config.endswith(b"\n"):
                f.write(b"\n")
            f.write((route + "=" + mapped_path + "\n").encode())

        os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 3
        while os.path.exists(proc_dir) and time.time() < deadline:
            time.sleep(0.05)
        if os.path.exists(proc_dir):
            os.kill(pid, signal.SIGKILL)
            time.sleep(0.2)

        replacement = subprocess.Popen(argv, executable=executable, cwd=cwd,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        url = "http://127.0.0.1:8080" + route
        assert wait_for_server(url, timeout=5), "Restarted C++ server did not become ready"
        response = requests.get(url, timeout=2)
        assert response.status_code == 200, "A route added to route_config.txt was not recognized"
        assert response.headers.get("Content-Type", "").lower().startswith("text/plain")
        assert response.content == expected, "Server did not return the exact contents of the dynamically mapped file"

        changed = ("changed mapped content " + uuid.uuid4().hex + "\n").encode()
        with open(mapped_path, "wb") as f:
            f.write(changed)
        response = requests.get(url, timeout=2)
        assert response.status_code == 200
        assert response.content == changed, "Server does not read the mapped file when serving a GET request"
    finally:
        with open(config_path, "wb") as f:
            f.write(original_config)
        try:
            os.unlink(mapped_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
