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
import time
import tarfile
import tempfile
from pathlib import PurePosixPath

import pytest
import requests

EXPECTED_FILES = {
    "src/main.c": b"data\n",
    "config/settings.conf": b"PORT=9000\nSECRET_TOKEN=REDACTED\nDEBUG=true\n",
    "settings.conf": b"SECRET_TOKEN=REDACTED\nLOG=1\n",
}


def proc_ppid(pid):
    data = open(f"/proc/{pid}/stat", "r").read()
    return int(data[data.rfind(")") + 2:].split()[1])


def proc_cmdline(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        return [x.decode(errors="replace") for x in f.read().split(b"\0") if x]


def listener_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                    state = fields[3]
                    if local_port == port and state == "0A":
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def socket_owners(inodes):
    owners = set()
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
                    owners.add(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def find_serving_process():
    deadline = time.time() + 5
    while time.time() < deadline:
        owners = socket_owners(listener_inodes(8080))
        for owner in owners:
            pid = owner
            seen = set()
            while pid > 1 and pid not in seen:
                seen.add(pid)
                try:
                    cmd = proc_cmdline(pid)
                except (FileNotFoundError, ProcessLookupError):
                    break
                if any(os.path.basename(arg) == "serve.sh" for arg in cmd):
                    try:
                        cwd = os.path.realpath(f"/proc/{pid}/cwd")
                    except OSError:
                        break
                    if cwd == "/home/user/www":
                        return owner, pid
                try:
                    pid = proc_ppid(pid)
                except (FileNotFoundError, ProcessLookupError, ValueError):
                    break
        time.sleep(0.1)
    pytest.fail("Port 8080 is not owned by a listening process descended from a running serve.sh serving /home/user/www")


def normalized_member_name(name):
    assert not name.startswith("/"), f"Archive contains absolute path: {name}"
    while name.startswith("./"):
        name = name[2:]
    path = PurePosixPath(name)
    assert ".." not in path.parts, f"Archive contains path traversal: {name}"
    return str(path)


def test_bash_serve_fixed_and_running():
    script_path = "/app/bash-serve/serve.sh"
    assert os.path.isfile(script_path), f"{script_path} is missing"
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable"

    with open(script_path, "r") as f:
        content = f.read()
        assert "-Z" not in content, f"The invalid '-Z' flag is still present in {script_path}"

    owner, serve_pid = find_serving_process()
    owner_cmd = proc_cmdline(owner)
    assert any(os.path.basename(arg) in ("nc", "netcat") for arg in owner_cmd), \
        f"The listener is not the netcat process launched by serve.sh: {owner_cmd}"
    assert serve_pid > 1


def test_cleaned_source_tree():
    actual = {}
    for root, dirs, files in os.walk("/home/user/projects"):
        for filename in files:
            full_path = os.path.join(root, filename)
            rel = os.path.relpath(full_path, "/home/user/projects").replace(os.sep, "/")
            assert not filename.endswith(".bak"), f"Backup file remains in project tree: {rel}"
            assert os.path.isfile(full_path) and not os.path.islink(full_path), f"Unexpected non-regular project file: {rel}"
            with open(full_path, "rb") as f:
                actual[rel] = f.read()
    assert actual == EXPECTED_FILES, "The cleaned project tree is incomplete or has modified/unexpected files"


def test_server_and_archive():
    # Establish that the listener belongs to serve.sh before retrieving from it.
    find_serving_process()

    url = "http://127.0.0.1:8080/clean_projects.tar.gz"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or fetch the archive at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response body: {response.text[:200]}"

    with tempfile.TemporaryDirectory() as tmpdir:
        tar_path = os.path.join(tmpdir, "clean_projects.tar.gz")
        with open(tar_path, "wb") as f:
            f.write(response.content)

        try:
            with tarfile.open(tar_path, "r:gz") as tar:
                archived = {}
                seen = set()
                for member in tar.getmembers():
                    name = normalized_member_name(member.name)
                    if name == ".":
                        assert member.isdir(), "Archive root entry is not a directory"
                        continue
                    assert name not in seen, f"Duplicate archive entry: {name}"
                    seen.add(name)
                    if member.isdir():
                        assert name in ("src", "config"), f"Unexpected directory in archive: {name}"
                        continue
                    assert member.isfile(), f"Archive contains a non-regular file: {name}"
                    extracted = tar.extractfile(member)
                    assert extracted is not None
                    archived[name] = extracted.read()

                assert archived == EXPECTED_FILES, "Archive does not contain the complete cleaned project tree"
                assert all(not name.endswith(".bak") for name in archived), "A .bak file is present in the archive"
                tar.extractall(path=tmpdir)
        except (tarfile.TarError, OSError) as e:
            pytest.fail(f"Failed to extract tarball. The file served might not be a valid gzip-compressed tarball: {e}")

        # Preserve the original specific backup assertions.
        main_c_bak = os.path.join(tmpdir, "src", "main.c.bak")
        old_bak = os.path.join(tmpdir, "config", "old.bak")
        assert not os.path.exists(main_c_bak), "Backup file main.c.bak was not deleted and is present in the archive."
        assert not os.path.exists(old_bak), "Backup file old.bak was not deleted and is present in the archive."

        config_settings = os.path.join(tmpdir, "config", "settings.conf")
        assert os.path.exists(config_settings), "config/settings.conf is missing from the archive. Ensure internal paths are relative to /home/user/projects/"
        with open(config_settings, "r") as f:
            content = f.read()
            assert "SECRET_TOKEN=REDACTED" in content, "config/settings.conf does not contain SECRET_TOKEN=REDACTED"
            assert "SECRET_TOKEN=abc123xyz" not in content, "config/settings.conf still contains the old secret token (abc123xyz)"

        root_settings = os.path.join(tmpdir, "settings.conf")
        assert os.path.exists(root_settings), "settings.conf is missing from the root of the archive. Ensure internal paths are relative to /home/user/projects/"
        with open(root_settings, "r") as f:
            content = f.read()
            assert "SECRET_TOKEN=REDACTED" in content, "settings.conf does not contain SECRET_TOKEN=REDACTED"
            assert "SECRET_TOKEN=dev_token" not in content, "settings.conf still contains the old secret token (dev_token)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
