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
import datetime
import os
import pwd
import re
import subprocess
import time
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
import requests

BASE = "http://127.0.0.1:8080"
AUTH = {"Authorization": "Bearer factory-edge-token-99"}
SUPERVISOR_CONF = "/home/user/supervisor/supervisord.conf"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def wait_for_server(timeout=15):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(BASE + "/invalid_path", timeout=1)
            return
        except requests.RequestException:
            time.sleep(0.2)
    pytest.fail("video server did not become ready")


def acl_entries(path, default=False):
    result = run(["getfacl", "-cp", path])
    assert result.returncode == 0, f"Failed to run getfacl on {path}: {result.stderr}"
    entries = {}
    prefix = "default:" if default else ""
    for raw in result.stdout.splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line.startswith(prefix):
            continue
        if default:
            line = line[len(prefix):]
        elif line.startswith("default:"):
            continue
        parts = line.split(":")
        if len(parts) == 3:
            entries[(parts[0], parts[1])] = parts[2]
    return entries


def test_acls():
    """Verify access ACLs and the ACLs inherited by newly created files."""
    directories = ["/home/user/app_data", "/home/user/logs"]
    user_uid = pwd.getpwnam("user").pw_uid

    for d in directories:
        assert os.path.isdir(d), f"Directory {d} does not exist"
        output = run(["getfacl", d])
        assert output.returncode == 0, f"Failed to run getfacl on {d}"
        assert re.search(r"default:group:users:r--", output.stdout), f"Default group ACL incorrect on {d}"
        assert re.search(r"default:other::---", output.stdout), f"Default other ACL incorrect on {d}"

        access = acl_entries(d)
        defaults = acl_entries(d, default=True)
        if os.stat(d).st_uid == user_uid:
            assert access.get(("user", "")) == "rwx", f"user lacks rwx access to {d}"
        else:
            assert access.get(("user", "user")) == "rwx", f"user lacks named rwx ACL on {d}"
        assert defaults.get(("group", "users")) == "r--", f"Default users group ACL incorrect on {d}"
        assert defaults.get(("other", "")) == "---", f"Default other ACL incorrect on {d}"

        probe = os.path.join(d, ".acl_verifier_probe")
        subprocess.run(["runuser", "-u", "user", "--", "sh", "-c", f"umask 000; : > '{probe}'"], check=True)
        try:
            inherited = acl_entries(probe)
            assert inherited.get(("group", "users")) == "r--", f"New files in {d} do not give users read-only access"
            assert inherited.get(("other", "")) == "---", f"New files in {d} allow access to others"
        finally:
            os.unlink(probe)


def test_supervisor_and_process():
    """Verify supervisord and video_server are running."""
    ps_output = run(["ps", "aux"]).stdout
    assert "supervisord" in ps_output, "supervisord is not running"
    assert "video_server" in ps_output, "video_server is not running"
    assert os.path.isfile("/home/user/src/video_server.c"), "C source is missing"
    assert os.path.isfile("/home/user/src/video_server"), "Compiled video_server is missing"
    assert os.access("/home/user/src/video_server", os.X_OK), "video_server is not executable"


def test_logrotate_config():
    """Verify the effective directives in the server.log stanza."""
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"Logrotate config {conf_path} does not exist"
    content = Path(conf_path).read_text()
    assert "/home/user/logs/server.log" in content, "Logrotate config does not target server.log"
    assert "daily" in content, "Logrotate config missing 'daily'"
    assert re.search(r"rotate\s+5", content), "Logrotate config missing 'rotate 5'"
    assert "compress" in content, "Logrotate config missing 'compress'"
    assert "copytruncate" in content, "Logrotate config missing 'copytruncate'"

    clean = re.sub(r"#.*", "", content)
    match = re.search(r"(?:^|\n)\s*/home/user/logs/server\.log\s*\{([^}]*)\}", clean, re.S)
    assert match, "No valid logrotate stanza for server.log"
    body = match.group(1)
    assert re.search(r"(?m)^\s*daily\s*$", body), "server.log stanza is not daily"
    assert re.search(r"(?m)^\s*rotate\s+5\s*$", body), "server.log stanza does not keep exactly 5 backups"
    assert re.search(r"(?m)^\s*compress\s*$", body), "server.log stanza does not enable compression"
    assert not re.search(r"(?m)^\s*nocompress\s*$", body), "server.log stanza disables compression"
    assert re.search(r"(?m)^\s*copytruncate\s*$", body), "server.log stanza does not use copytruncate"


def test_http_server():
    """Retain the original fixture check and HTTP authorization/path checks."""
    wait_for_server()
    try:
        response = requests.get(BASE + "/anomaly", headers=AUTH, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server: {e}")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
    assert response.text.strip() == "142", f"Expected body '142', got '{response.text}'"

    response = requests.get(BASE + "/anomaly", timeout=5)
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"
    response = requests.get(BASE + "/invalid_path", headers=AUTH, timeout=5)
    assert response.status_code == 404, f"Expected 404 Not Found, got {response.status_code}"


def make_video(first_black):
    tmp = "/app/.camera_feed_verifier.mp4"
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "color=c=white:s=80x60:r=10",
        "-vf", f"drawbox=x=0:y=0:w=80:h=60:color=black:t=fill:enable='eq(n,{first_black})'",
        "-frames:v", "60", "-c:v", "libx264", "-crf", "0", "-pix_fmt", "yuv420p", tmp,
    ]
    result = run(cmd)
    assert result.returncode == 0, result.stderr
    os.replace(tmp, "/app/camera_feed.mp4")


def derive_first_black():
    proc = subprocess.Popen([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", "/app/camera_feed.mp4",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-"
    ], stdout=subprocess.PIPE)
    frame_size = 80 * 60 * 3
    index = 0
    answer = None
    while True:
        frame = proc.stdout.read(frame_size)
        if not frame:
            break
        assert len(frame) == frame_size, "ffmpeg returned a partial frame"
        if not any(frame):
            answer = index
            break
        index += 1
    proc.kill()
    proc.wait()
    assert answer is not None, "Generated test video has no black frame"
    return answer


def restart_under_supervisor():
    old = set(run(["pgrep", "-x", "video_server"]).stdout.split())
    assert old, "video_server was not running before restart test"
    for pid in old:
        os.kill(int(pid), 15)
    deadline = time.time() + 15
    while time.time() < deadline:
        current = set(run(["pgrep", "-x", "video_server"]).stdout.split())
        if current and current.isdisjoint(old):
            wait_for_server()
            return
        time.sleep(0.2)
    pytest.fail("supervisor did not automatically restart video_server")


def latest_log_time(path, status):
    pattern = re.compile(rf"^\[(\d{{4}}-\d{{2}}-\d{{2}} \d{{2}}:\d{{2}}:\d{{2}})\] {re.escape(path)} {status}\s*$")
    deadline = time.time() + 5
    while time.time() < deadline:
        if os.path.exists("/home/user/logs/server.log"):
            lines = Path("/home/user/logs/server.log").read_text().splitlines()
            for line in reversed(lines):
                match = pattern.match(line)
                if match:
                    return datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=ZoneInfo("Europe/Berlin"))
        time.sleep(0.1)
    pytest.fail(f"No log entry found for {path} {status}")


def test_dynamic_video_analysis_and_berlin_time():
    """Use independently derived answers so a fixed response cannot pass."""
    localtime = Path("/etc/localtime")
    was_link = localtime.is_symlink()
    old_target = os.readlink(localtime) if was_link else None
    old_bytes = None if was_link else localtime.read_bytes()
    try:
        localtime.unlink()
        localtime.symlink_to("/usr/share/zoneinfo/UTC")

        for black_frame in (7, 43):
            make_video(black_frame)
            expected = derive_first_black()
            assert expected == black_frame
            restart_under_supervisor()
            before = datetime.datetime.now(ZoneInfo("Europe/Berlin")) - datetime.timedelta(seconds=2)
            response = requests.get(BASE + "/anomaly", headers=AUTH, timeout=10)
            after = datetime.datetime.now(ZoneInfo("Europe/Berlin")) + datetime.timedelta(seconds=2)
            assert response.status_code == 200
            assert response.text.strip() == str(expected), f"Service did not analyze the current video; expected {expected}, got {response.text!r}"
            logged = latest_log_time("/anomaly", 200)
            assert before <= logged <= after, f"Log timestamp {logged} is not current Europe/Berlin time"
    finally:
        if localtime.exists() or localtime.is_symlink():
            localtime.unlink()
        if was_link:
            localtime.symlink_to(old_target)
        else:
            localtime.write_bytes(old_bytes)


def test_server_logs_and_locale_configuration():
    """Verify every log line and that the application configures the required locale."""
    log_path = "/home/user/logs/server.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist"
    logs = Path(log_path).read_text().splitlines()
    assert logs, "Log file is empty"
    log_pattern = re.compile(r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] /\S+ \d{3}$")
    for line in logs:
        assert log_pattern.search(line), f"Log line format incorrect: {line}"

    source = Path("/home/user/src/video_server.c").read_text(errors="replace")
    deployed = source
    if os.path.isfile(SUPERVISOR_CONF):
        deployed += "\n" + Path(SUPERVISOR_CONF).read_text(errors="replace")
    assert re.search(r"de_DE(?:\.UTF-?8|\.utf8)", deployed, re.I), "de_DE.UTF-8 is not configured"
    assert re.search(r"setlocale\s*\(|newlocale\s*\(|(?:LC_ALL|LC_TIME)\s*=", deployed), "Application does not activate the configured locale"
    assert "Europe/Berlin" in deployed, "Europe/Berlin is not configured"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
