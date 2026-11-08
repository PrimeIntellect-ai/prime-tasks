#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import socket
import stat
import subprocess
import tempfile

import pytest

HOME = '/home/user'
SOURCE = f'{HOME}/uptime_monitor.c'
SCRIPT = f'{HOME}/setup_env.sh'
EXECUTABLE = f'{HOME}/uptime_monitor'
SOURCE_EXECUTABLE = '/tmp/uptime_monitor_from_source'
LOG = f'{HOME}/vm_uptime.log'


@pytest.fixture(scope='session', autouse=True)
def rebuild_with_setup_script():
    outputs = [
        EXECUTABLE,
        f'{HOME}/vm_data.img',
        f'{HOME}/simulated_fstab',
        f'{HOME}/vm_logrotate.conf',
    ]

    assert os.path.isfile(SOURCE), 'uptime_monitor.c does not exist or is not a regular file'
    assert os.path.isfile(SCRIPT), 'setup_env.sh does not exist or is not a regular file'
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, 'setup_env.sh is not executable'

    for path in outputs:
        if os.path.lexists(path):
            assert not os.path.isdir(path), f'{path} must be a file, not a directory'
            os.unlink(path)

    result = subprocess.run(
        ['/usr/sbin/runuser', '-u', 'user', '--', SCRIPT],
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, (
        f'setup_env.sh failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    # Independently compile the submitted source so placeholder source cannot be
    # hidden behind a fabricated executable.
    compile_result = subprocess.run(
        ['gcc', SOURCE, '-o', SOURCE_EXECUTABLE],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f'uptime_monitor.c does not compile with gcc:\n{compile_result.stderr}'
    )
    assert os.path.isfile(SOURCE_EXECUTABLE)
    assert os.access(SOURCE_EXECUTABLE, os.X_OK)


def log_size():
    if not os.path.exists(LOG):
        return 0
    assert os.path.isfile(LOG), 'vm_uptime.log is not a regular file'
    return os.path.getsize(LOG)


def appended_bytes(previous_size):
    assert os.path.isfile(LOG), 'vm_uptime.log was not created'
    with open(LOG, 'rb') as f:
        f.seek(previous_size)
        return f.read()


def run_success_case(executable):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        before = log_size()
        result = subprocess.run(
            [executable, str(port)], capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f'{executable} should exit with code 0 for a listening port; '
            f'got {result.returncode}'
        )
        assert appended_bytes(before) == b'STATUS: OK\n', (
            f'{executable} did not append exactly STATUS: OK\\n on success'
        )


def run_failure_case(executable, port):
    before = log_size()
    result = subprocess.run(
        [executable, str(port)], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 1, (
        f'{executable} should exit with code 1 for a closed port; '
        f'got {result.returncode}'
    )
    assert appended_bytes(before) == b'STATUS: FAIL\n', (
        f'{executable} did not append exactly STATUS: FAIL\\n on failure'
    )


def test_uptime_monitor_c_exists():
    assert os.path.exists(SOURCE), 'uptime_monitor.c does not exist'


def test_setup_env_sh_exists_and_executable():
    assert os.path.exists(SCRIPT), 'setup_env.sh does not exist'
    st = os.stat(SCRIPT)
    assert st.st_mode & stat.S_IXUSR, 'setup_env.sh is not executable'


def test_setup_created_real_executable():
    assert os.path.isfile(EXECUTABLE), 'uptime_monitor executable does not exist'
    assert os.access(EXECUTABLE, os.X_OK), 'uptime_monitor is not executable'
    with open(EXECUTABLE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'setup_env.sh did not create a compiled ELF executable'


def test_vm_data_img_exists_size_and_ext4():
    path = f'{HOME}/vm_data.img'
    assert os.path.exists(path), 'vm_data.img does not exist'
    assert os.path.isfile(path), 'vm_data.img is not a regular file'
    assert os.path.getsize(path) == 10 * 1024 * 1024, 'vm_data.img is not exactly 10MB'

    result = subprocess.run(['file', path], capture_output=True, text=True)
    assert 'ext4 filesystem data' in result.stdout, (
        f'vm_data.img is not an ext4 filesystem: {result.stdout}'
    )

    fscheck = subprocess.run(
        ['dumpe2fs', '-h', path], capture_output=True, text=True, timeout=15
    )
    assert fscheck.returncode == 0, f'vm_data.img is not a readable ext4 filesystem: {fscheck.stderr}'


def test_simulated_fstab():
    path = f'{HOME}/simulated_fstab'
    assert os.path.exists(path), 'simulated_fstab does not exist'

    with open(path, 'r') as f:
        content = f.read().strip()

    pattern = r'^\/home\/user\/vm_data\.img\s+\/mnt\/vm_data\s+ext4\s+loop\s+0\s+0$'
    assert re.search(pattern, content, re.MULTILINE), (
        f'simulated_fstab does not contain the correct mount entry. Content: {content}'
    )
    assert len(content.splitlines()) == 1, 'simulated_fstab must contain exactly one line'
    assert re.fullmatch(pattern, content), 'simulated_fstab contains extra fields or entries'


def test_vm_logrotate_conf():
    path = f'{HOME}/vm_logrotate.conf'
    assert os.path.exists(path), 'vm_logrotate.conf does not exist'

    with open(path, 'r') as f:
        content = f.read()

    # Preserve the original presence assertions.
    assert '/home/user/vm_uptime.log' in content, 'Logrotate config missing target log file'
    assert 'daily' in content, "Logrotate config missing 'daily'"
    assert re.search(r'rotate\s+4', content), "Logrotate config missing 'rotate 4'"
    assert 'compress' in content, "Logrotate config missing 'compress'"
    assert 'missingok' in content, "Logrotate config missing 'missingok'"

    # Check actual directives in the target log block rather than comments or substrings.
    uncommented = '\n'.join(line.split('#', 1)[0] for line in content.splitlines())
    block_match = re.search(
        r'(?ms)^\s*/home/user/vm_uptime\.log\s*\{(.*?)^\s*\}', uncommented
    )
    assert block_match, 'No valid logrotate block for /home/user/vm_uptime.log'
    directives = [line.strip().split() for line in block_match.group(1).splitlines() if line.strip()]
    assert ['daily'] in directives, 'Target log block does not specify daily rotation'
    assert ['rotate', '4'] in directives, 'Target log block does not specify rotate 4'
    assert ['compress'] in directives, 'Target log block does not specify compress'
    assert ['missingok'] in directives, 'Target log block does not specify missingok'
    assert ['nocompress'] not in directives, 'Target log block disables compression'

    # Parse the complete configuration with logrotate using a safe temporary log path.
    with tempfile.TemporaryDirectory(prefix='logrotate_check_') as directory:
        safe_log = os.path.join(directory, 'vm_uptime.log')
        safe_conf = os.path.join(directory, 'vm_logrotate.conf')
        open(safe_log, 'a').close()
        checked_content = content.replace('/home/user/vm_uptime.log', safe_log)
        with open(safe_conf, 'w') as f:
            f.write(checked_content)
        parsed = subprocess.run(
            ['logrotate', '--debug', safe_conf], capture_output=True, text=True, timeout=15
        )
        assert parsed.returncode == 0, (
            f'vm_logrotate.conf is not valid logrotate syntax:\n{parsed.stdout}\n{parsed.stderr}'
        )


def test_successful_connection_behavior_on_runtime_ports():
    # Exercise both the executable produced by setup_env.sh and an independent
    # compilation of the submitted C source on verifier-selected listening ports.
    run_success_case(EXECUTABLE)
    run_success_case(SOURCE_EXECUTABLE)


def test_vm_uptime_log_initial_execution():
    path = LOG
    assert os.path.exists(path), 'vm_uptime.log does not exist'
    with open(path, 'r') as f:
        content = f.read()
    assert 'STATUS: OK' in content, (
        "vm_uptime.log does not contain 'STATUS: OK'. Did you run ./uptime_monitor 8080?"
    )


def test_uptime_monitor_executable_behavior():
    assert os.path.exists(EXECUTABLE), 'uptime_monitor executable does not exist'
    assert os.access(EXECUTABLE, os.X_OK), 'uptime_monitor is not executable'

    # Preserve the original fixed-port failure assertion.
    run_failure_case(EXECUTABLE, 9999)
    with open(LOG, 'r') as f:
        lines = f.readlines()
    assert len(lines) > 0, 'vm_uptime.log is empty'
    assert lines[-1].strip() == 'STATUS: FAIL', (
        "uptime_monitor did not append 'STATUS: FAIL' to vm_uptime.log for a failed connection"
    )


def test_failure_behavior_on_verifier_selected_closed_ports():
    # Holding a loopback port bound but not listening makes it closed while
    # preventing another process from claiming the verifier-selected port.
    for executable in (EXECUTABLE, SOURCE_EXECUTABLE):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as closed_socket:
            closed_socket.bind(('127.0.0.1', 0))
            port = closed_socket.getsockname()[1]
            run_failure_case(executable, port)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
