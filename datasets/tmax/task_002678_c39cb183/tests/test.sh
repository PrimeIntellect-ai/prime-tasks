#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import secrets
import shutil
import socket
import subprocess
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

import pytest

SOURCE_DIR = "/app/sys-exporter-1.2.0"
BINARY = os.path.join(SOURCE_DIR, "sys-exporter")
ARCHIVE = "/app/metrics_bundle.tar.gz"
MOUNT_DIR = "/home/user/mnt_data"


def http_get(url, timeout=5):
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.status, response.read()


def test_makefile_fixed_and_source_builds_and_runs():
    """Keep the flag check, then compile and exercise the submitted source dynamically."""
    makefile_path = os.path.join(SOURCE_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"{makefile_path} is missing."
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-pthread" in content, "Makefile is still missing the -pthread flag."

    with tempfile.TemporaryDirectory() as build_dir, tempfile.TemporaryDirectory() as data_dir:
        shutil.copy2(makefile_path, os.path.join(build_dir, "Makefile"))
        shutil.copy2(os.path.join(SOURCE_DIR, "main.cpp"), os.path.join(build_dir, "main.cpp"))

        dry_run = subprocess.run(
            ["make", "-n", "-B", "sys-exporter"], cwd=build_dir,
            capture_output=True, text=True, check=True
        )
        assert "-pthread" in dry_run.stdout + dry_run.stderr, \
            "The active sys-exporter build command does not use -pthread."

        subprocess.run(["make", "clean"], cwd=build_dir, check=True,
                       capture_output=True, text=True)
        subprocess.run(["make", "sys-exporter"], cwd=build_dir, check=True,
                       capture_output=True, text=True)
        built_binary = os.path.join(build_dir, "sys-exporter")
        assert os.path.isfile(built_binary) and os.access(built_binary, os.X_OK)
        with open(built_binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Compiled sys-exporter is not an ELF binary."

        token = secrets.token_hex(24)
        payload = json.dumps({"runtime_token": token, "value": secrets.randbelow(1000000)}).encode() + b"\n"
        with open(os.path.join(data_dir, "system_stats.json"), "wb") as f:
            f.write(payload)

        probe = socket.socket()
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
        probe.close()

        env = os.environ.copy()
        env["SERVER_PORT"] = str(port)
        env["TARGET_DIR"] = data_dir
        proc = subprocess.Popen([built_binary], env=env, stdout=subprocess.DEVNULL,
                                stderr=subprocess.PIPE)
        try:
            deadline = time.time() + 5
            while True:
                if proc.poll() is not None:
                    stderr = proc.stderr.read().decode(errors="replace")
                    pytest.fail(f"Freshly compiled sys-exporter exited early: {stderr}")
                try:
                    status, body = http_get(f"http://127.0.0.1:{port}/system_stats.json", 0.5)
                    break
                except Exception:
                    if time.time() >= deadline:
                        pytest.fail("Freshly compiled sys-exporter did not start listening.")
                    time.sleep(0.1)
            assert status == 200
            assert body == payload, "Compiled service did not serve the runtime-generated file."
            with pytest.raises(urllib.error.HTTPError) as exc:
                http_get(f"http://127.0.0.1:{port}/{secrets.token_hex(12)}", 2)
            assert exc.value.code == 404
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)


def test_main_cpp_fixed():
    """Check that main.cpp has the typo fixed."""
    main_cpp_path = os.path.join(SOURCE_DIR, "main.cpp")
    assert os.path.isfile(main_cpp_path), f"{main_cpp_path} is missing."
    with open(main_cpp_path, "r") as f:
        content = f.read()
    assert "TARGET_DIR" in content, "main.cpp does not contain the corrected 'TARGET_DIR'."
    assert "TARGT_DIR" not in content, "main.cpp still contains the 'TARGT_DIR' typo."


def test_installed_binary_exists():
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Compiled binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not an ELF executable."


def test_archive_is_mounted_read_only_and_contents_match():
    assert os.path.isfile(ARCHIVE), f"Archive {ARCHIVE} is missing."
    assert os.path.isdir(MOUNT_DIR), f"Mount directory {MOUNT_DIR} is missing."

    result = subprocess.run(
        ["findmnt", "-rn", "-T", MOUNT_DIR, "-o", "TARGET,FSTYPE,OPTIONS"],
        capture_output=True, text=True, check=True
    )
    fields = result.stdout.strip().split(None, 2)
    assert len(fields) == 3 and fields[0] == MOUNT_DIR, \
        f"{MOUNT_DIR} is not a distinct mounted filesystem: {result.stdout!r}"
    fstype, options = fields[1], fields[2]
    assert "archivemount" in fstype.lower(), \
        f"{MOUNT_DIR} is not mounted using archivemount (filesystem is {fstype})."
    assert "ro" in options.split(","), f"Archive mount is not read-only: {options}"

    with tarfile.open(ARCHIVE, "r:gz") as bundle:
        expected = bundle.extractfile("system_stats.json").read()
    with open(os.path.join(MOUNT_DIR, "system_stats.json"), "rb") as f:
        mounted = f.read()
    assert mounted == expected, "Mounted data does not match metrics_bundle.tar.gz."


def test_cron_job_configured():
    """Check that the user has the correct cron job configured."""
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"],
            capture_output=True, text=True, check=True
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to read crontab for 'user'. Error: {e.stderr}")

    expected_cron = r"@reboot\s+/home/user/start_exporter\.sh"
    assert re.search(expected_cron, crontab_content), \
        "Cron job for @reboot /home/user/start_exporter.sh is missing or incorrect."


def test_profile_exports():
    """Check that .profile contains the required exports."""
    profile_path = "/home/user/.profile"
    assert os.path.isfile(profile_path), f"{profile_path} is missing."
    with open(profile_path, "r") as f:
        content = f.read()
    assert re.search(r"export\s+SERVER_PORT=8080\b", content), \
        "export SERVER_PORT=8080 is missing in .profile."
    assert re.search(r"export\s+TARGET_DIR=/home/user/mnt_data\b", content), \
        "export TARGET_DIR=/home/user/mnt_data is missing in .profile."


def test_startup_script_contains_required_steps():
    script = "/home/user/start_exporter.sh"
    assert os.path.isfile(script), f"{script} is missing."
    assert os.access(script, os.X_OK), f"{script} is not executable."
    with open(script, "r") as f:
        lines = [line for line in f if not re.match(r"^\s*#", line)]
    content = "\n".join(lines)
    assert re.search(r"(?:source|\.)\s+(?:~/\.profile|/home/user/\.profile|\$HOME/\.profile)\b", content), \
        "Startup script does not source the user's .profile."
    archive_mount_line = next((line for line in lines if "archivemount" in line), "")
    assert ARCHIVE in archive_mount_line and MOUNT_DIR in archive_mount_line, \
        "Startup script does not establish the required archive mount."
    assert re.search(r"/app/sys-exporter-1\.2\.0/sys-exporter[^\n]*&", content), \
        "Startup script does not start the compiled sys-exporter in the background."


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    parts = line.split()
                    if len(parts) > 9 and parts[1].rsplit(":", 1)[1].upper() == wanted and parts[3] == "0A":
                        inodes.add(parts[9])
        except FileNotFoundError:
            pass

    pids = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        for fd in glob.glob(procdir + "/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                pids.add(pid)
                break
    return pids


def test_live_listener_is_compiled_binary_with_required_environment():
    pids = listener_pids(8080)
    assert pids, "No process is listening on TCP port 8080."
    for pid in pids:
        try:
            assert os.path.samefile(f"/proc/{pid}/exe", BINARY), \
                f"Process {pid} listening on port 8080 is not the compiled sys-exporter binary."
            with open(f"/proc/{pid}/environ", "rb") as f:
                environment = f.read().split(b"\0")
        except FileNotFoundError:
            pytest.fail(f"Listener process {pid} disappeared during verification.")
        assert b"SERVER_PORT=8080" in environment
        assert b"TARGET_DIR=/home/user/mnt_data" in environment


def test_http_endpoint_serves_archive_data():
    """Derive the answer from the archive and verify exact bytes and JSON semantics."""
    with tarfile.open(ARCHIVE, "r:gz") as bundle:
        expected_body = bundle.extractfile("system_stats.json").read()
    status, actual_body = http_get("http://127.0.0.1:8080/system_stats.json", 5)
    assert status == 200, f"Expected HTTP 200 OK, got {status}."
    assert actual_body == expected_body, "HTTP response does not contain the archive member's exact data."
    try:
        actual_data = json.loads(actual_body)
        expected_data = json.loads(expected_body)
    except ValueError as e:
        pytest.fail(f"Response or archive member is not valid JSON: {e}")
    assert actual_data == expected_data, f"Expected JSON {expected_data}, got {actual_data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
