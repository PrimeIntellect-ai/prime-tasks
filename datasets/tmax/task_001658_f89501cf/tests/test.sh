#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import glob
import gzip
import os
import signal
import stat
import subprocess
import time


def test_capacity_planner_script():
    script_path = '/home/user/capacity_planner.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert st.st_mode & stat.S_IXUSR, f"Script {script_path} is not executable."


def test_qemu_mock_running():
    try:
        output = subprocess.check_output(['pgrep', '-f', 'qemu_mock.py -vnc :2']).decode('utf-8')
        assert output.strip(), "qemu_mock.py is not running with '-vnc :2'."
    except subprocess.CalledProcessError:
        assert False, "qemu_mock.py is not running with '-vnc :2'."


def test_logrotate_conf():
    conf_path = '/home/user/rotate.conf'
    assert os.path.isfile(conf_path), f"Logrotate config {conf_path} does not exist."
    with open(conf_path, 'r') as f:
        content = f.read()

    assert '/home/user/vm_capacity.log' in content, "Log file path missing in rotate.conf."
    assert 'rotate 2' in content, "'rotate 2' missing in rotate.conf."
    assert 'compress' in content, "'compress' missing in rotate.conf."
    assert 'missingok' in content, "'missingok' missing in rotate.conf."
    assert 'size 10' in content.replace('bytes', '').replace('b', '').replace('c', ''), "Size directive for 10 bytes missing in rotate.conf."


def test_rotated_log_contents():
    rotated_log_path = '/home/user/vm_capacity.log.1.gz'
    assert os.path.isfile(rotated_log_path), f"Rotated log {rotated_log_path} does not exist. Did logrotate run properly?"

    with gzip.open(rotated_log_path, 'rt') as f:
        content = f.read()

    assert "STATUS: DOWN - ACTION: STARTING VM" in content, "First log entry missing in rotated log."
    assert "STATUS: UP - ACTION: NONE" in content, "Second log entry missing in rotated log."


def _qemu_pids():
    found = []
    for path in glob.glob('/proc/[0-9]*/cmdline'):
        try:
            pid = int(path.split('/')[2])
            with open(path, 'rb') as f:
                argv = [x.decode(errors='replace') for x in f.read().split(b'\0') if x]
        except (OSError, ValueError):
            continue
        for i, arg in enumerate(argv):
            if arg == '/home/user/qemu_mock.py' and argv[i + 1:i + 3] == ['-vnc', ':2']:
                found.append(pid)
                break
    return found


def _kill_qemu():
    for pid in _qemu_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while _qemu_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in _qemu_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while _qemu_pids() and time.time() < deadline:
        time.sleep(0.05)
    assert not _qemu_pids(), "Could not stop the existing mock VM before behavioral testing."


def _port_5902_listening():
    # Inspect the kernel's TCP table without consuming a connection from the
    # mock's deliberately small accept queue.
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 4 and fields[1].split(':')[-1].upper() == '170E' and fields[3] == '0A':
                        return True
        except FileNotFoundError:
            pass
    return False


def _run_planner():
    result = subprocess.run(
        ['/home/user/capacity_planner.sh'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )
    assert result.returncode == 0, f"capacity_planner.sh failed: {result.stderr}"


def _run_logrotate(state):
    result = subprocess.run(
        ['logrotate', '-s', state, '/home/user/rotate.conf'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"logrotate rejected or failed to apply rotate.conf: {result.stderr}"


def test_supervision_behavior_and_logrotate_behavior():
    log_path = '/home/user/vm_capacity.log'
    down = 'STATUS: DOWN - ACTION: STARTING VM'
    up = 'STATUS: UP - ACTION: NONE'

    _kill_qemu()
    assert not _port_5902_listening(), "TCP port 5902 is unexpectedly occupied before the DOWN-path test."
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass

    _run_planner()
    with open(log_path) as f:
        assert f.read().splitlines() == [down], "The DOWN run did not append exactly the required DOWN status."

    deadline = time.time() + 4
    while (not _qemu_pids() or not _port_5902_listening()) and time.time() < deadline:
        time.sleep(0.05)
    assert _qemu_pids(), "The DOWN run did not execute /home/user/qemu_mock.py -vnc :2."
    assert _port_5902_listening(), "The mock VM started by the DOWN run did not listen on TCP port 5902."

    _run_planner()
    with open(log_path) as f:
        assert f.read().splitlines() == [down, up], "The UP run did not append exactly the required UP status."
    assert _qemu_pids(), "The supervised mock VM is no longer running after the UP check."

    # Exercise the submitted configuration rather than trusting its keywords.
    # Ten bytes must not rotate, while eleven bytes must rotate and compress.
    _kill_qemu()
    for path in glob.glob(log_path + '.*'):
        if os.path.isfile(path):
            os.remove(path)
    state = '/tmp/verifier-logrotate.state'
    try:
        os.remove(state)
    except FileNotFoundError:
        pass

    with open(log_path, 'wb') as f:
        f.write(b'1234567890')
    _run_logrotate(state)
    assert os.path.isfile(log_path), "rotate.conf rotated a log that did not exceed 10 bytes."
    assert not glob.glob(log_path + '.[0-9]*'), "rotate.conf rotated a log that did not exceed 10 bytes."

    with open(log_path, 'wb') as f:
        f.write(b'12345678901')
    _run_logrotate(state)
    assert os.path.isfile(log_path + '.1.gz'), "A log exceeding 10 bytes was not rotated and compressed."
    with gzip.open(log_path + '.1.gz', 'rb') as f:
        assert f.read() == b'12345678901', "The compressed rotated log has incorrect contents."

    # Repeated rotations must retain exactly two compressed old copies.
    for payload in (b'abcdefghijk', b'ABCDEFGHIJK'):
        with open(log_path, 'wb') as f:
            f.write(payload)
        _run_logrotate(state)
    assert os.path.isfile(log_path + '.1.gz'), "Newest compressed rotation is missing."
    assert os.path.isfile(log_path + '.2.gz'), "Second compressed rotation is missing."
    assert not glob.glob(log_path + '.3*'), "rotate.conf retained more than two old copies."

    # missingok must work behaviorally when the active log is absent.
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass
    _run_logrotate(state)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
