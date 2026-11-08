#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import tarfile
import time
import uuid

import pytest

SERVICES = ['auth', 'data', 'web']
SERVICE_PATHS = {svc: f'/home/user/services/{svc}.py' for svc in SERVICES}


def read_cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return [part.decode('utf-8', errors='ignore') for part in f.read().split(b'\0') if part]
    except OSError:
        return []


def process_is_running(pid):
    try:
        with open(f'/proc/{pid}/stat', 'r') as f:
            state = f.read().split()[2]
        return state != 'Z'
    except (OSError, IndexError):
        return False


def process_runs_script(pid, script_path):
    expected = os.path.realpath(script_path)
    for arg in read_cmdline(pid):
        if arg.startswith('/') and os.path.realpath(arg) == expected:
            return True
    return False


def read_environment(pid):
    with open(f'/proc/{pid}/environ', 'rb') as f:
        entries = f.read().split(b'\0')
    result = {}
    for item in entries:
        if b'=' in item:
            key, value = item.split(b'=', 1)
            result[key.decode('utf-8', errors='ignore')] = value.decode('utf-8', errors='ignore')
    return result


def descendants(root_pid):
    found = set()
    frontier = {root_pid}
    while frontier:
        parents = frontier
        frontier = set()
        try:
            proc_entries = [x for x in os.listdir('/proc') if x.isdigit()]
        except OSError:
            return found
        for entry in proc_entries:
            pid = int(entry)
            if pid in found or pid == root_pid:
                continue
            try:
                with open(f'/proc/{pid}/stat', 'r') as f:
                    fields = f.read().split()
                ppid = int(fields[3])
            except (OSError, ValueError, IndexError):
                continue
            if ppid in parents:
                found.add(pid)
                frontier.add(pid)
    return found


def find_service_descendant(monitor_pid, service):
    matches = []
    for pid in descendants(monitor_pid):
        if process_is_running(pid) and process_runs_script(pid, SERVICE_PATHS[service]):
            matches.append(pid)
    return matches


def wait_for(predicate, timeout, description):
    deadline = time.monotonic() + timeout
    last_value = None
    while time.monotonic() < deadline:
        last_value = predicate()
        if last_value:
            return last_value
        time.sleep(0.1)
    pytest.fail(f'Timed out waiting for {description}. Last observed value: {last_value!r}')


def test_deploy_monitor_exists():
    path = '/home/user/deploy_monitor.py'
    assert os.path.exists(path), f'File {path} does not exist. The deploy_monitor.py script is missing.'
    assert os.path.isfile(path), f'Path {path} is not a file.'


def test_backup_exists_and_valid():
    backup_path = '/home/user/backups/auth_backup.tar.gz'
    assert os.path.exists(backup_path), f'Backup file {backup_path} does not exist. The monitor may not have detected the crash or created the backup.'
    assert os.path.isfile(backup_path), f'Path {backup_path} is not a file.'
    assert tarfile.is_tarfile(backup_path), f'Backup file {backup_path} is not a valid tar archive.'


def test_deployment_report_exists_and_valid():
    report_path = '/home/user/deployment_report.json'
    assert os.path.exists(report_path), f'Deployment report {report_path} does not exist.'
    assert os.path.isfile(report_path), f'Path {report_path} is not a file.'

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {report_path} is not valid JSON.')

    assert report.get('auth_restarted') is True, "The 'auth_restarted' field in the report must be true."

    backups = report.get('backups_created', [])
    assert isinstance(backups, list), "'backups_created' must be a list."
    assert 'auth_backup.tar.gz' in backups, "'auth_backup.tar.gz' must be in the 'backups_created' list."

    pids = report.get('active_pids', {})
    assert isinstance(pids, dict), "'active_pids' must be a dictionary."
    for svc in SERVICES:
        assert svc in pids, f"Service '{svc}' is missing from 'active_pids'."
        assert isinstance(pids[svc], int) and not isinstance(pids[svc], bool), f"PID for '{svc}' must be an integer."
    assert len({pids[svc] for svc in SERVICES}) == 3, 'The three services must have distinct PIDs.'


def test_running_processes_and_environment():
    report_path = '/home/user/deployment_report.json'
    if not os.path.exists(report_path):
        pytest.fail(f'Cannot verify processes because {report_path} is missing.')

    with open(report_path, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('Cannot verify processes because report is invalid JSON.')

    pids = report.get('active_pids', {})
    if not isinstance(pids, dict) or not all(k in pids for k in SERVICES):
        pytest.fail("Cannot verify processes because 'active_pids' structure is invalid.")

    assert len({pids[svc] for svc in SERVICES}) == 3, 'The reported service PIDs are not distinct.'
    for svc in SERVICES:
        pid = pids[svc]
        env_file = f'/proc/{pid}/environ'
        assert os.path.exists(env_file), f"Process {pid} for service '{svc}' is not running."
        assert process_is_running(pid), f"Process {pid} for service '{svc}' is not running."
        assert process_runs_script(pid, SERVICE_PATHS[svc]), f"PID {pid} does not run the named service script {SERVICE_PATHS[svc]}."

        try:
            env_dict = read_environment(pid)
        except Exception as e:
            pytest.fail(f"Could not read environment for PID {pid} (service '{svc}'): {e}")

        assert env_dict.get('TZ') == 'UTC', f"Service '{svc}' (PID {pid}) does not have TZ=UTC in its environment."
        assert env_dict.get('LC_ALL') == 'C.UTF-8', f"Service '{svc}' (PID {pid}) does not have LC_ALL=C.UTF-8 in its environment."


def test_z_monitor_executes_backs_up_and_restarts_crashed_service():
    monitor_path = '/home/user/deploy_monitor.py'
    backup_path = '/home/user/backups/auth_backup.tar.gz'
    auth_data = '/home/user/data/auth'
    os.makedirs('/home/user/backups', exist_ok=True)
    os.makedirs(auth_data, exist_ok=True)

    token = uuid.uuid4().hex
    marker_name = f'verifier_marker_{token}.txt'
    marker_path = os.path.join(auth_data, marker_name)
    marker_data = f'dynamic backup challenge {token}\n'.encode()
    with open(marker_path, 'wb') as f:
        f.write(marker_data)

    try:
        os.remove(backup_path)
    except FileNotFoundError:
        pass

    monitor = subprocess.Popen(
        ['python3', monitor_path],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    try:
        initial = {}
        for svc in SERVICES:
            matches = wait_for(
                lambda svc=svc: find_service_descendant(monitor.pid, svc),
                8,
                f'the executed monitor to launch {svc}.py',
            )
            assert len(matches) == 1, f'The monitor launched multiple {svc}.py processes: {matches}'
            initial[svc] = matches[0]

        assert monitor.poll() is None, 'deploy_monitor.py exited instead of continuously monitoring its children.'
        assert len(set(initial.values())) == 3, 'The monitor did not launch three distinct service processes.'
        assert not os.path.exists(backup_path), 'The auth backup was created before auth.py crashed.'

        for svc, pid in initial.items():
            env = read_environment(pid)
            assert env.get('TZ') == 'UTC', f'Freshly launched {svc}.py lacks TZ=UTC.'
            assert env.get('LC_ALL') == 'C.UTF-8', f'Freshly launched {svc}.py lacks LC_ALL=C.UTF-8.'

        os.kill(initial['auth'], signal.SIGKILL)

        def restarted_auth():
            matches = find_service_descendant(monitor.pid, 'auth')
            fresh = [pid for pid in matches if pid != initial['auth']]
            return fresh[0] if fresh else None

        new_auth_pid = wait_for(restarted_auth, 6, 'auth.py to be restarted after SIGKILL')
        assert monitor.poll() is None, 'deploy_monitor.py stopped while handling the auth.py crash.'
        new_env = read_environment(new_auth_pid)
        assert new_env.get('TZ') == 'UTC', 'Restarted auth.py lacks TZ=UTC.'
        assert new_env.get('LC_ALL') == 'C.UTF-8', 'Restarted auth.py lacks LC_ALL=C.UTF-8.'

        def valid_dynamic_backup():
            if not os.path.isfile(backup_path):
                return False
            try:
                with open(backup_path, 'rb') as f:
                    if f.read(2) != b'\x1f\x8b':
                        return False
                with tarfile.open(backup_path, 'r:gz') as archive:
                    members = [m for m in archive.getmembers() if os.path.basename(m.name.rstrip('/')) == marker_name]
                    if len(members) != 1 or not members[0].isfile():
                        return False
                    extracted = archive.extractfile(members[0])
                    return extracted is not None and extracted.read() == marker_data
            except (OSError, tarfile.TarError):
                return False

        wait_for(valid_dynamic_backup, 6, 'a gzip auth backup containing the live auth data')
    finally:
        try:
            os.killpg(monitor.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            monitor.wait(timeout=2)
        except subprocess.TimeoutExpired:
            monitor.kill()
        try:
            os.remove(marker_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
