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
import shutil
import signal
import socket
import subprocess
import tempfile
import time

import requests

OBS_DIR = "/home/user/obs"
VIDEO = "/app/dashboard_capture.mp4"


def test_cron_job_exists():
    """Check that the logrotate cron job exists for the user."""
    try:
        output = subprocess.check_output(
            ['crontab', '-l', '-u', 'user'], stderr=subprocess.STDOUT
        ).decode('utf-8')
    except subprocess.CalledProcessError:
        output = ""

    assert "logrotate /home/user/obs/logrotate.conf" in output, "Cron job for logrotate not found in user's crontab."
    assert any(
        line.split()[1] == "*" and line.split()[2] == "*"
        for line in output.splitlines()
        if "logrotate" in line
    ), "Cron job does not appear to be scheduled hourly."


def test_logrotate_conf():
    """Check the contents of the logrotate configuration."""
    conf_path = "/home/user/obs/logrotate.conf"
    assert os.path.exists(conf_path), f"logrotate.conf not found at {conf_path}"
    with open(conf_path, 'r') as f:
        content = f.read()

    assert "daily" in content, "logrotate.conf missing 'daily'"
    assert "rotate 3" in content, "logrotate.conf missing 'rotate 3'"
    assert "compress" in content, "logrotate.conf missing 'compress'"
    assert "copytruncate" in content, "logrotate.conf missing 'copytruncate'"
    parsed = subprocess.run(
        ['logrotate', '-d', conf_path], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT
    )
    assert parsed.returncode == 0, f"Invalid logrotate configuration:\n{parsed.stdout}"


def _cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ""


def _ppid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            data = f.read()
        return int(data[data.rfind(')') + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def _is_descendant(pid, ancestors):
    seen = set()
    while pid > 1 and pid not in seen:
        if pid in ancestors:
            return True
        seen.add(pid)
        pid = _ppid(pid)
    return False


def _listener_pids(port):
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] == '0A' and int(fields[1].split(':')[1], 16) == port:
                        inodes.add(fields[9])
        except OSError:
            pass

    result = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                match = re.fullmatch(r'socket:\[(\d+)\]', target)
                if match and match.group(1) in inodes:
                    result.add(int(name))
                    break
        except OSError:
            pass
    return result


def test_start_sh_running_and_supervises_service():
    """Check that the real wrapper owns the service and restarts it after a crash."""
    output = subprocess.check_output(['ps', 'aux']).decode('utf-8')
    assert "start.sh" in output, "start.sh process is not running"

    script = f"{OBS_DIR}/start.sh"
    assert os.path.isfile(script), "start.sh is missing"
    syntax = subprocess.run(['bash', '-n', script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert syntax.returncode == 0, f"start.sh has invalid shell syntax: {syntax.stderr}"
    content = open(script).read()
    assert 'OBS_PORT=9090' in content and 'OBS_TOKEN=OBS-TUNING-2024' in content
    assert 'metrics.log' in content, "start.sh does not redirect application output to metrics.log"
    assert re.search(r'\bwhile\b', content) and re.search(r'\bgo\s+build\b', content), "start.sh must build and repeatedly run the exporter"

    wrappers = {
        int(pid) for pid in os.listdir('/proc')
        if pid.isdigit() and '/home/user/obs/start.sh' in _cmdline(int(pid))
    }
    assert wrappers, "No running /home/user/obs/start.sh wrapper was found"

    listeners = _listener_pids(9090)
    owned = {pid for pid in listeners if _is_descendant(pid, wrappers)}
    assert owned, "The service on port 9090 is not a child of start.sh"
    old_pid = next(iter(owned))
    os.kill(old_pid, signal.SIGKILL)

    replacement = None
    deadline = time.time() + 15
    while time.time() < deadline:
        current = _listener_pids(9090)
        candidates = {
            pid for pid in current
            if pid != old_pid and _is_descendant(pid, wrappers)
        }
        if candidates:
            replacement = next(iter(candidates))
            break
        time.sleep(0.2)
    assert replacement is not None, "start.sh did not restart the exporter after it was killed"


def test_http_endpoints():
    """Verify the metrics server endpoints."""
    base_url = "http://127.0.0.1:9090"

    for _ in range(5):
        try:
            res = requests.get(f"{base_url}/health", timeout=2)
            if res.status_code == 200:
                break
        except requests.RequestException:
            time.sleep(1)
    else:
        assert False, "Health endpoint did not return 200 OK after retries."

    res_health = requests.get(f"{base_url}/health")
    assert res_health.status_code == 200, f"/health returned {res_health.status_code}"

    res_metrics_no_auth = requests.get(f"{base_url}/metrics")
    assert res_metrics_no_auth.status_code in (401, 403), f"/metrics without auth returned {res_metrics_no_auth.status_code}"

    headers = {"Authorization": "Bearer OBS-TUNING-2024"}
    res_metrics_auth = requests.get(f"{base_url}/metrics", headers=headers)
    assert res_metrics_auth.status_code == 200, f"/metrics with auth returned {res_metrics_auth.status_code}"
    assert "critical_inode_frames_total 7" in res_metrics_auth.text, "Metrics output did not contain 'critical_inode_frames_total 7'"


def _free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def _make_video(path, critical_positions, frame_count=19):
    """Create a verifier-owned video and return its independently known count."""
    critical_positions = set(critical_positions)
    command = [
        'ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'rawvideo', '-pixel_format', 'rgb24', '-video_size', '32x32',
        '-framerate', '10', '-i', '-', '-frames:v', str(frame_count),
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', path
    ]
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for index in range(frame_count):
            if index in critical_positions:
                pixel = bytes((255, 0, 0))
            elif index % 2:
                pixel = bytes((0, 0, 0))
            else:
                pixel = bytes((255, 255, 255))
            proc.stdin.write(pixel * (32 * 32))
        proc.stdin.close()
        stderr = proc.stderr.read()
        returncode = proc.wait()
    finally:
        if proc.poll() is None:
            proc.kill()
    assert returncode == 0, stderr.decode(errors='replace')
    return len(critical_positions)


def _run_exporter(binary, expected, token):
    port = _free_port()
    env = os.environ.copy()
    env['OBS_PORT'] = str(port)
    env['OBS_TOKEN'] = token
    proc = subprocess.Popen(
        [binary], cwd=OBS_DIR, env=env, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, start_new_session=True
    )
    try:
        base = f'http://127.0.0.1:{port}'
        deadline = time.time() + 20
        last_error = None
        while time.time() < deadline:
            if proc.poll() is not None:
                output = proc.stdout.read().decode(errors='replace')
                raise AssertionError(f'Exporter exited before serving: {output}')
            try:
                response = requests.get(base + '/health', timeout=1)
                if response.status_code == 200:
                    break
            except requests.RequestException as exc:
                last_error = exc
            time.sleep(0.2)
        else:
            raise AssertionError(f'Exporter did not serve /health on OBS_PORT: {last_error}')

        assert requests.get(base + '/metrics', timeout=2).status_code in (401, 403)
        assert requests.get(
            base + '/metrics', headers={'Authorization': 'Bearer wrong-token'}, timeout=2
        ).status_code in (401, 403), "Exporter accepted an incorrect bearer token"
        response = requests.get(
            base + '/metrics', headers={'Authorization': f'Bearer {token}'}, timeout=2
        )
        assert response.status_code == 200
        match = re.search(r'^critical_inode_frames_total\s+(\d+)\s*$', response.text, re.MULTILINE)
        assert match, f'Missing Prometheus metric in response: {response.text!r}'
        assert int(match.group(1)) == expected, f'Expected {expected} analyzed red frames, got {match.group(1)}'
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()


def test_exporter_source_analyzes_changed_videos():
    """Build the submitted Go source and exercise it against fresh, varying videos."""
    source = f'{OBS_DIR}/exporter.go'
    assert os.path.isfile(source) and not os.path.islink(source), "exporter.go is missing or is not a regular submitted file"
    assert os.path.getsize(source) > 0, "exporter.go is empty"

    with tempfile.TemporaryDirectory() as tempdir:
        binary = os.path.join(tempdir, 'exporter-under-test')
        build = subprocess.run(
            ['go', 'build', '-o', binary, source], cwd=OBS_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            timeout=60
        )
        assert build.returncode == 0, f'exporter.go did not compile:\n{build.stdout}'

        backup = os.path.join(tempdir, 'dashboard_capture.original.mp4')
        shutil.copy2(VIDEO, backup)
        try:
            trials = [({1, 4}, 'dynamic-token-one'), ({0, 3, 7, 11, 16}, 'dynamic-token-two')]
            for positions, token in trials:
                generated = os.path.join(tempdir, f'generated-{len(positions)}.mp4')
                expected = _make_video(generated, positions)
                os.replace(generated, VIDEO)
                _run_exporter(binary, expected, token)
        finally:
            shutil.copy2(backup, VIDEO)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
