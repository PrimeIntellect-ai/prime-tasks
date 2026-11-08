#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import tarfile
import time
import urllib.request
import uuid
from pathlib import Path

HOME = Path("/home/user")
MARKERS = {}


def _stop_existing_test_servers():
    victims = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            argv = (proc / "cmdline").read_bytes().split(b"\0")
            args = [item.decode("utf-8", "replace") for item in argv if item]
        except (OSError, PermissionError):
            continue
        if "http.server" in args and ("9001" in args or "9002" in args):
            victims.append(int(proc.name))

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.5)


def test_00_deploy_script_exists_is_python_and_performs_rollout():
    script = HOME / "deploy.py"
    assert script.is_file(), "/home/user/deploy.py is missing"
    assert not script.is_symlink(), "/home/user/deploy.py must be a regular Python file"

    source = script.read_text(encoding="utf-8")
    assert source.strip(), "/home/user/deploy.py is empty"
    compile(source, str(script), "exec")

    _stop_existing_test_servers()

    nonce = uuid.uuid4().hex
    releases = {
        "service_a": ("v1 a", "v2 a"),
        "service_b": ("v1 b", "v2 b"),
    }
    for service, (v1_text, v2_text) in releases.items():
        old_marker = f"old-{service}-{nonce}"
        new_marker = f"new-{service}-{nonce}"
        MARKERS[service] = {"old": old_marker, "new": new_marker}
        (HOME / "releases" / f"{service}_v1" / "index.html").write_text(
            f"{v1_text}\n{old_marker}\n", encoding="utf-8"
        )
        (HOME / "releases" / f"{service}_v2" / "index.html").write_text(
            f"{v2_text}\n{new_marker}\n", encoding="utf-8"
        )

        link = HOME / "deployments" / service / "current"
        if os.path.lexists(link):
            link.unlink()
        os.symlink(str(HOME / "releases" / f"{service}_v1"), link)

        backup = HOME / "backups" / f"{service}_backup.tar.gz"
        if backup.exists() or backup.is_symlink():
            backup.unlink()
        pid_file = HOME / "run" / f"{service}.pid"
        if pid_file.exists() or pid_file.is_symlink():
            pid_file.unlink()

    with open(os.devnull, "wb") as devnull:
        result = subprocess.run(
            ["runuser", "-u", "user", "--", "python3", str(script)],
            cwd=str(HOME),
            stdin=subprocess.DEVNULL,
            stdout=devnull,
            stderr=devnull,
            timeout=20,
            check=False,
        )
    assert result.returncode == 0, f"deploy.py exited with status {result.returncode}"
    time.sleep(1)


def test_services_json_updated():
    config_path = Path("/home/user/services.json")
    assert config_path.is_file(), "services.json is missing"

    with open(config_path, "r") as f:
        data = json.load(f)

    assert data.get("service_a", {}).get("host") == "127.0.0.1", "service_a host not updated to 127.0.0.1"
    assert data.get("service_a", {}).get("port") == 9001, "service_a port not updated to 9001"
    assert data.get("service_b", {}).get("host") == "127.0.0.1", "service_b host not updated to 127.0.0.1"
    assert data.get("service_b", {}).get("port") == 9002, "service_b port not updated to 9002"


def test_symlinks_updated():
    symlinks = {
        "/home/user/deployments/service_a/current": "/home/user/releases/service_a_v2",
        "/home/user/deployments/service_b/current": "/home/user/releases/service_b_v2",
    }
    for link, expected_target in symlinks.items():
        link_path = Path(link)
        assert link_path.is_symlink(), f"{link} is not a symlink"
        actual_target = os.readlink(link)
        assert actual_target == expected_target, f"Symlink {link} points to {actual_target}, expected {expected_target}"


def test_backups_created_and_contain_v1_data():
    backups = {
        "service_a": ("/home/user/backups/service_a_backup.tar.gz", "v1 a"),
        "service_b": ("/home/user/backups/service_b_backup.tar.gz", "v1 b"),
    }
    for service, (backup_path, expected_content) in backups.items():
        assert Path(backup_path).is_file(), f"Backup file missing: {backup_path}"
        found_original = False
        found_marker = False
        with tarfile.open(backup_path, "r:gz") as tar:
            for member in tar.getmembers():
                if member.isfile() and member.name.endswith("index.html"):
                    extracted = tar.extractfile(member)
                    if extracted:
                        content = extracted.read().decode("utf-8")
                        found_original = found_original or expected_content in content
                        found_marker = found_marker or MARKERS[service]["old"] in content
        assert found_original, f"Expected content '{expected_content}' not found in any index.html inside {backup_path}"
        assert found_marker, f"Backup {backup_path} was not created from the reset v1 release"


def test_http_servers_running_and_serving_v2():
    endpoints = {
        "service_a": ("http://127.0.0.1:9001/index.html", "v2 a"),
        "service_b": ("http://127.0.0.1:9002/index.html", "v2 b"),
    }
    for service, (url, expected_content) in endpoints.items():
        try:
            with urllib.request.urlopen(url, timeout=2) as response:
                content = response.read().decode("utf-8")
                assert expected_content in content, f"Expected '{expected_content}' in response from {url}, got '{content}'"
                assert MARKERS[service]["new"] in content, f"Server at {url} is not serving the reset v2 release"
        except Exception as e:
            assert False, f"Failed to fetch {url}: {e}"


def test_pid_files_match_running_processes():
    services = {
        "service_a": (9001, "/home/user/deployments/service_a/current"),
        "service_b": (9002, "/home/user/deployments/service_b/current"),
    }
    for service, (port, directory) in services.items():
        pid_file = Path(f"/home/user/run/{service}.pid")
        assert pid_file.is_file(), f"PID file missing: {pid_file}"
        pid_str = pid_file.read_text().strip()
        assert pid_str.isdigit(), f"PID file {pid_file} does not contain a valid integer PID"
        pid = int(pid_str)

        try:
            os.kill(pid, 0)
        except OSError:
            assert False, f"Process with PID {pid} (from {pid_file}) is not running"

        try:
            argv = [
                item.decode("utf-8", "replace")
                for item in Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
                if item
            ]
        except OSError as exc:
            assert False, f"Cannot inspect process {pid} from {pid_file}: {exc}"
        assert "http.server" in argv, f"PID {pid} is not a Python HTTP server"
        assert str(port) in argv, f"PID {pid} was not started for port {port}"
        assert "--bind" in argv and "127.0.0.1" in argv, f"PID {pid} is not bound as configured"
        assert "--directory" in argv and directory in argv, f"PID {pid} is not serving {directory}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
