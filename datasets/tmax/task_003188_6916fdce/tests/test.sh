#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import signal
import time
import urllib.request
import urllib.error
import pytest

SUPERVISOR = '/home/user/service/supervisor.sh'
DAEMON = '/home/user/service/daemon.py'
HEALTH_URL = 'http://127.0.0.1:8181/health'
EXPECTED_OUTPUT = '{"status": "healthy", "uptime": "stable"}'


def proc_cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return [part.decode('utf-8', 'replace') for part in f.read().split(b'\0') if part]
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return []


def proc_ppid(pid):
    try:
        with open(f'/proc/{pid}/status', 'r') as f:
            for line in f:
                if line.startswith('PPid:'):
                    return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
        pass
    return None


def all_processes():
    result = {}
    for name in os.listdir('/proc'):
        if name.isdigit():
            pid = int(name)
            cmd = proc_cmdline(pid)
            if cmd:
                result[pid] = (proc_ppid(pid), cmd)
    return result


def is_supervisor_command(cmd):
    return bool(cmd) and SUPERVISOR in cmd and os.path.basename(cmd[0]) in ('bash', 'sh', 'supervisor.sh')


def is_daemon_command(cmd):
    return (
        len(cmd) >= 2
        and os.path.basename(cmd[0]).startswith('python3')
        and DAEMON in cmd[1:]
    )


def descendants(root_pid, processes):
    found = set()
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _cmd) in processes.items():
            if pid not in found and (ppid == root_pid or ppid in found):
                found.add(pid)
                changed = True
    return found


def managed_daemons(supervisor_pid):
    processes = all_processes()
    return [
        pid for pid in descendants(supervisor_pid, processes)
        if pid in processes and is_daemon_command(processes[pid][1])
    ]


def endpoint_is_healthy():
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=1) as response:
            return response.status == 200 and response.read().decode('utf-8').strip() == EXPECTED_OUTPUT
    except Exception:
        return False


def wait_for_managed_daemon(supervisor_pid, excluded=frozenset(), timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for pid in managed_daemons(supervisor_pid):
            if pid in excluded:
                continue
            time.sleep(0.35)
            if pid in managed_daemons(supervisor_pid) and endpoint_is_healthy():
                return pid
        time.sleep(0.1)
    return None


def find_live_supervisor():
    deadline = time.time() + 3
    while time.time() < deadline:
        processes = all_processes()
        for pid, (_ppid, cmd) in processes.items():
            if is_supervisor_command(cmd):
                daemon_pid = wait_for_managed_daemon(pid, timeout=1)
                if daemon_pid is not None:
                    return pid, daemon_pid
        time.sleep(0.1)
    return None, None


def test_config_symlink_fixed():
    symlink_path = '/home/user/service/config.json'
    assert os.path.exists(symlink_path), f"Symlink {symlink_path} does not exist."
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."
    target = os.readlink(symlink_path)
    expected_target = '/home/user/service/configs/production.json'
    assert target == expected_target, f"Symlink points to {target} instead of {expected_target}."


def test_cache_directory_created():
    cache_dir = '/home/user/service/cache'
    assert os.path.exists(cache_dir), f"Cache directory {cache_dir} does not exist."
    assert os.path.isdir(cache_dir), f"{cache_dir} is not a directory."


def test_supervisor_script_exists_and_valid():
    script_path = SUPERVISOR
    assert os.path.exists(script_path), f"Supervisor script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    with open(script_path, 'r') as f:
        content = f.read()

    # Retain the original assertions.
    assert re.search(r'\bwhile\b', content), "Supervisor script does not contain a 'while' loop."
    assert 'daemon.py' in content, "Supervisor script does not seem to execute daemon.py."

    # Ignore comments and require the requested command inside an unconditional loop.
    code = '\n'.join(line.split('#', 1)[0] for line in content.splitlines())
    condition = r'(?:true|:|/bin/true|\[\s*(?:1|true)\s*\]|\[\[\s*(?:1|true)\s*\]\]|\(\(\s*1\s*\)\))'
    loop_re = re.compile(
        r'(?ms)^[ \t]*while[ \t]+' + condition
        + r'[ \t]*(?:;[ \t]*)?(?:\n[ \t]*)?do\b(?P<body>.*?)^[ \t]*done\b'
    )
    loops = list(loop_re.finditer(code))
    assert loops, "Supervisor script does not contain an unconditional infinite while loop."
    daemon_re = re.compile(
        r'(?m)^[ \t]*(?:exec[ \t]+)?(?:/usr/bin/)?python3[ \t]+'
        r'/home/user/service/daemon\.py(?:[ \t]|$)'
    )
    assert any(daemon_re.search(match.group('body')) for match in loops), (
        "python3 /home/user/service/daemon.py is not executed inside the infinite loop."
    )

    # Verify the submitted script is the live supervisor and really restarts its daemon.
    supervisor_pid, daemon_pid = find_live_supervisor()
    assert supervisor_pid is not None, (
        "No running supervisor.sh process with a managed daemon.py child was found."
    )

    previous = {daemon_pid}
    for attempt in range(2):
        os.kill(daemon_pid, signal.SIGKILL)
        replacement = wait_for_managed_daemon(supervisor_pid, excluded=previous, timeout=5)
        assert replacement is not None, (
            f"Supervisor did not restart daemon.py after forced exit #{attempt + 1}."
        )
        assert proc_cmdline(supervisor_pid), "Supervisor exited instead of remaining in the background."
        daemon_pid = replacement
        previous.add(replacement)


def test_health_check_output():
    health_file = '/home/user/service/health_check.txt'
    assert os.path.exists(health_file), f"Health check output file {health_file} does not exist."
    assert os.path.isfile(health_file), f"{health_file} is not a file."

    with open(health_file, 'r') as f:
        content = f.read().strip()

    expected_output = EXPECTED_OUTPUT
    assert content == expected_output, f"Health check file content is incorrect. Expected: '{expected_output}', Got: '{content}'"


def test_service_is_running():
    # Verify that the service is actually listening and responding
    url = HEALTH_URL
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Service returned HTTP {response.status} instead of 200."
            data = response.read().decode('utf-8').strip()
            assert data == EXPECTED_OUTPUT, "Service returned unexpected payload."
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to the service at {url}. Is the supervisor running in the background? Error: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
