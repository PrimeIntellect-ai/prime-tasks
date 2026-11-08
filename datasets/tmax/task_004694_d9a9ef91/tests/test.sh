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
import ipaddress
import json
import os
import signal
import stat
import subprocess
import tempfile
import time
import wave

import pytest
import requests

IP_FILE = "/home/user/master_ip.txt"
REPO = "/home/user/repo_data"
SERVER = "/home/user/server.go"
PORT_HEX = format(8080, "04X")


def read_master_ip():
    assert os.path.isfile(IP_FILE) and not os.path.islink(IP_FILE), f"File {IP_FILE} does not exist or is not a regular file."
    with open(IP_FILE, "r") as f:
        content = f.read().strip()
    try:
        parsed = ipaddress.ip_address(content)
    except ValueError as e:
        pytest.fail(f"{IP_FILE} does not contain only a valid IP address: {e}")
    assert parsed.version == 4 and str(parsed) == content, f"Expected a canonical IPv4 address in {IP_FILE}, found {content!r}."
    return content


def wav_payload(path):
    with wave.open(path, "rb") as w:
        return (w.getparams(), w.readframes(w.getnframes()))


def regular_file_count():
    count = 0
    for root, dirs, files in os.walk(REPO, followlinks=False):
        for name in files:
            mode = os.lstat(os.path.join(root, name)).st_mode
            if stat.S_ISREG(mode):
                count += 1
    return count


def listening_inodes():
    found = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == "0A" and fields[1].split(":")[-1].upper() == PORT_HEX:
                        found.add(fields[9])
        except FileNotFoundError:
            pass
    return found


def pids_for_inodes(inodes):
    result = set()
    if not inodes:
        return result
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def stop_existing_listener():
    pids = pids_for_inodes(listening_inodes())
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listening_inodes() and time.time() < deadline:
        time.sleep(0.05)
    for pid in pids_for_inodes(listening_inodes()):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while listening_inodes() and time.time() < deadline:
        time.sleep(0.05)
    assert not listening_inodes(), "Could not clear the pre-existing listener on port 8080."


def ipv4_wildcard_listener_pids():
    inodes = set()
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, port = fields[1].split(":")
            if fields[3] == "0A" and port.upper() == PORT_HEX and address == "00000000":
                inodes.add(fields[9])
    return pids_for_inodes(inodes)


def test_master_ip_file():
    ip = read_master_ip()
    fd, candidate_wav = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        sentence = (
            "Attention team, the repository migration is complete. Please note that "
            f"the new master server IP is {ip} and should be updated in all clients."
        )
        subprocess.run(["espeak", "-w", candidate_wav, sentence], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert wav_payload(candidate_wav) == wav_payload("/app/artifact_memo.wav"), \
            f"The IPv4 address in {IP_FILE} was not the address dictated by the supplied audio memo."
    finally:
        try:
            os.unlink(candidate_wav)
        except FileNotFoundError:
            pass


def test_symlink_loop_removed():
    loop_symlink = "/home/user/repo_data/v1/loop_dir"
    assert not os.path.exists(loop_symlink) and not os.path.islink(loop_symlink), \
        f"The infinite loop symlink {loop_symlink} should be removed."


def test_regular_files_intact():
    files = [
        "/home/user/repo_data/v1/bin/artifact-a.bin",
        "/home/user/repo_data/v1/bin/artifact-b.bin",
        "/home/user/repo_data/v2/bin/artifact-c.bin",
        "/home/user/repo_data/v2/bin/artifact-d.bin",
        "/home/user/repo_data/readme.txt",
    ]
    for path in files:
        assert os.path.isfile(path) and not os.path.islink(path), f"Regular file {path} is missing or was modified to a symlink."
    assert regular_file_count() == len(files), "The repository does not contain exactly the original regular files."


def test_valid_symlink_intact():
    symlink_path = "/home/user/repo_data/latest-c"
    target_path = "/home/user/repo_data/v2/bin/artifact-c.bin"
    assert os.path.islink(symlink_path), f"Valid symlink {symlink_path} was removed or modified."
    assert os.readlink(symlink_path) == target_path, f"Valid symlink {symlink_path} points to incorrect target."


def test_go_api_service():
    assert os.path.isfile(SERVER) and not os.path.islink(SERVER), f"Required Go source file {SERVER} is missing or is not a regular file."

    listing = subprocess.run(
        ["go", "list", "-deps", "-json", SERVER],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert listing.returncode == 0, f"The Go source does not compile or cannot be analyzed:\n{listing.stderr}"
    decoder = json.JSONDecoder()
    pos = 0
    packages = []
    while pos < len(listing.stdout):
        while pos < len(listing.stdout) and listing.stdout[pos].isspace():
            pos += 1
        if pos >= len(listing.stdout):
            break
        package, pos = decoder.raw_decode(listing.stdout, pos)
        packages.append(package)
    assert packages, "go list returned no package information for server.go."
    assert packages[-1].get("Name") == "main", "server.go must define an executable Go main package."
    nonstandard = [p.get("ImportPath", "<unknown>") for p in packages
                   if not p.get("Standard", False) and p.get("ImportPath") != "command-line-arguments"]
    assert not nonstandard, f"The server uses non-standard-library Go dependencies: {nonstandard}"

    expected = {
        "master_ip": read_master_ip(),
        "artifact_count": regular_file_count(),
    }

    stop_existing_listener()
    proc = subprocess.Popen(
        ["go", "run", SERVER],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        response = None
        last_error = None
        deadline = time.time() + 20
        while time.time() < deadline:
            if proc.poll() is not None:
                stdout, stderr = proc.communicate(timeout=1)
                pytest.fail(f"go run server.go exited before serving requests. stdout={stdout!r}, stderr={stderr!r}")
            try:
                response = requests.get("http://127.0.0.1:8080/api/status", timeout=0.5)
                break
            except requests.exceptions.RequestException as e:
                last_error = e
                time.sleep(0.1)
        assert response is not None, f"Failed to connect to the Go API: {last_error}"

        listener_pids = ipv4_wildcard_listener_pids()
        assert listener_pids, "The service is not listening on the required IPv4 wildcard address 0.0.0.0:8080."
        go_listeners = []
        for pid in listener_pids:
            result = subprocess.run(["go", "version", "-m", f"/proc/{pid}/exe"], text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode == 0:
                go_listeners.append(pid)
        assert go_listeners, "The process actually listening on port 8080 is not a compiled Go executable."

        assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}."
        try:
            data = response.json()
        except requests.exceptions.JSONDecodeError:
            pytest.fail(f"Response body is not valid JSON: {response.text}")
        assert data == expected, f"API returned incorrect JSON payload. Expected {expected}, got {data}."

        root_response = requests.get("http://127.0.0.1:8080/", timeout=2)
        assert root_response.status_code == 404, "The server must not expose an additional root endpoint."
        trailing_response = requests.get("http://127.0.0.1:8080/api/status/", timeout=2)
        assert trailing_response.status_code == 404, "Only the exact /api/status endpoint should be exposed."
        post_response = requests.post("http://127.0.0.1:8080/api/status", timeout=2)
        assert post_response.status_code != 200, "/api/status must only accept GET requests."
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
