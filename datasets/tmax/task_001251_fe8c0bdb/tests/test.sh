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
import secrets
import signal
import subprocess
import time

import pytest
import requests

APP_DIR = "/app/docserve-1.0"
BINARY = os.path.join(APP_DIR, "server")
INDEX = "/home/user/data/index.csv"
EXTRACTED = "/home/user/data/extracted"
DOCS = "/home/user/www/docs"
BASE_URL = "http://127.0.0.1:8080"


def test_extracted_files_exist():
    assert os.path.isdir(EXTRACTED), f"Directory {EXTRACTED} does not exist. Did you extract the archive?"

    file1 = os.path.join(EXTRACTED, "intro.md")
    file2 = os.path.join(EXTRACTED, "advanced/io.md")

    assert os.path.isfile(file1), f"File {file1} not found. Archive extraction might have failed."
    assert os.path.isfile(file2), f"File {file2} not found. Archive extraction might have failed."


def test_symlinks_created():
    assert os.path.isdir(DOCS), f"Directory {DOCS} does not exist."

    symlink1 = os.path.join(DOCS, "101.txt")
    symlink2 = os.path.join(DOCS, "102.txt")

    assert os.path.islink(symlink1), f"{symlink1} is not a symlink."
    assert os.path.islink(symlink2), f"{symlink2} is not a symlink."

    target1 = os.readlink(symlink1)
    target2 = os.readlink(symlink2)

    assert target1 == "/home/user/data/extracted/intro.md", f"Symlink {symlink1} points to {target1}, expected /home/user/data/extracted/intro.md"
    assert target2 == "/home/user/data/extracted/advanced/io.md", f"Symlink {symlink2} points to {target2}, expected /home/user/data/extracted/advanced/io.md"


def test_server_binary_compiled():
    assert os.path.isfile(BINARY), f"Compiled server binary not found at {BINARY}. Did you fix the Makefile and run make?"
    assert os.access(BINARY, os.X_OK), f"Server binary {BINARY} is not executable."


def test_server_responses():
    try:
        resp1 = requests.get(f"{BASE_URL}/docs/101.txt", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/docs/101.txt. Is the server running? Error: {e}")

    assert resp1.status_code == 200, f"Expected status code 200 for /docs/101.txt, got {resp1.status_code}"
    assert "Introduction to Data Parsing" in resp1.text, f"Unexpected body for /docs/101.txt: {resp1.text}"

    try:
        resp2 = requests.get(f"{BASE_URL}/docs/102.txt", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}/docs/102.txt. Is the server running? Error: {e}")

    assert resp2.status_code == 200, f"Expected status code 200 for /docs/102.txt, got {resp2.status_code}"
    assert "Advanced C++ File I/O" in resp2.text, f"Unexpected body for /docs/102.txt: {resp2.text}"


def kill_port_8080_listeners():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)


def test_fresh_build_and_runtime_csv_processing():
    source_path = os.path.join(APP_DIR, "server.cpp")
    with open(source_path, encoding="utf-8") as f:
        source = f.read()

    setup_match = re.search(r"void\s+setup_docs\s*\([^)]*\)\s*\{(.*?)\}\s*\n\s*int\s+main", source, re.S)
    assert setup_match, "Could not find an implemented setup_docs function in server.cpp"
    setup_body = setup_match.group(1)
    assert re.search(r"\b(?:std::)?(?:i?fstream)\b|\bmmap\s*\(", setup_body), "setup_docs must read the CSV using C++ file streaming or mmap"
    assert re.search(r"\bsymlink\s*\(", setup_body), "setup_docs must create symbolic links using symlink()"

    # Add unpredictable rows only after the agent has finished. This ensures the
    # rebuilt C++ program must actually parse the index rather than hardcode the fixtures.
    with open(INDEX, encoding="utf-8") as f:
        used_ids = {line.split(",", 1)[0] for line in f if "," in line}

    token = secrets.token_hex(8)
    cases = []
    for i in range(3):
        while True:
            doc_id = str(200000000 + secrets.randbelow(700000000))
            if doc_id not in used_ids:
                used_ids.add(doc_id)
                break
        relative = f"verify_{token}/level{i}/document_{secrets.token_hex(4)}.md"
        content = f"dynamic documentation {token} item {i} {secrets.token_hex(12)}\n".encode()
        absolute = os.path.join(EXTRACTED, relative)
        os.makedirs(os.path.dirname(absolute), exist_ok=True)
        with open(absolute, "wb") as f:
            f.write(content)
        link = os.path.join(DOCS, f"{doc_id}.txt")
        try:
            os.unlink(link)
        except FileNotFoundError:
            pass
        cases.append((doc_id, relative, absolute, link, content))

    with open(INDEX, "a", encoding="utf-8") as f:
        for doc_id, relative, _, _, _ in cases:
            f.write(f"{doc_id},{relative}\n")

    kill_port_8080_listeners()

    # Require the submitted Makefile to produce the artifact from scratch.
    try:
        os.unlink(BINARY)
    except FileNotFoundError:
        pass
    result = subprocess.run(["make", "-C", APP_DIR], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    assert result.returncode == 0, f"A fresh make failed:\n{result.stdout}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "make did not produce an executable server"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The server produced by make is not a compiled ELF binary"

    proc = subprocess.Popen([BINARY], cwd=APP_DIR, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)

    deadline = time.time() + 8
    last_error = None
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Freshly built server exited early with status {proc.returncode}")
        try:
            response = requests.get(f"{BASE_URL}/docs/101.txt", timeout=0.5)
            if response.status_code == 200:
                break
        except requests.RequestException as e:
            last_error = e
        time.sleep(0.15)
    else:
        pytest.fail(f"Freshly built server did not start listening on 127.0.0.1:8080: {last_error}")

    assert proc.poll() is None, "Freshly built server is not remaining active"
    for doc_id, _, absolute, link, content in cases:
        assert os.path.islink(link), f"setup_docs did not create dynamic symlink {link}"
        assert os.readlink(link) == absolute, f"Dynamic symlink {link} does not point to the required absolute extracted path"
        response = requests.get(f"{BASE_URL}/docs/{doc_id}.txt", timeout=5)
        assert response.status_code == 200, f"Expected 200 for dynamically indexed document {doc_id}, got {response.status_code}"
        assert response.content == content, f"Incorrect response body for dynamically indexed document {doc_id}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
