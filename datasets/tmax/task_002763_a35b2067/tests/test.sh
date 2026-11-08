#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import signal
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import pytest

HOME = Path('/home/user')
LOGS = HOME / 'logs'


def wait_for(predicate, timeout=3.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


def test_tenant_deduplication():
    baseline = HOME / 'tenants/baseline/config.json'
    assert baseline.is_file(), f'Missing baseline config at {baseline}'
    baseline_inode = baseline.stat().st_ino

    identical_tenants = [
        HOME / 'tenants/tenant_1/config.json',
        HOME / 'tenants/tenant_3/config.json',
        HOME / 'tenants/tenant_4/config.json',
    ]
    different_tenants = [
        HOME / 'tenants/tenant_2/config.json',
        HOME / 'tenants/tenant_5/config.json',
    ]

    for path in identical_tenants:
        assert path.is_file(), f'Missing config file at {path}'
        assert path.stat().st_ino == baseline_inode, f'{path} is not hardlinked to the baseline'
    for path in different_tenants:
        assert path.is_file(), f'Missing config file at {path}'
        assert path.stat().st_ino != baseline_inode, f'{path} was incorrectly hardlinked to the baseline'

    script = HOME / 'link_assets.sh'
    assert script.is_file(), f'Missing deduplication script at {script}'

    suffix = uuid.uuid4().hex
    same_dir = HOME / f'tenants/tenant_dynamic_same_{suffix}'
    diff_dir = HOME / f'tenants/tenant_dynamic_diff_{suffix}'
    same_dir.mkdir()
    diff_dir.mkdir()
    same_path = same_dir / 'config.json'
    diff_path = diff_dir / 'config.json'
    same_path.write_bytes(baseline.read_bytes())
    different_data = ('{"dynamic":"' + suffix + '"}\n').encode()
    diff_path.write_bytes(different_data)
    diff_inode = diff_path.stat().st_ino

    result = subprocess.run(['/bin/bash', str(script)], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f'Deduplication script failed: {result.stderr}'
    assert same_path.stat().st_ino == baseline.stat().st_ino, 'A newly discovered identical tenant was not hardlinked'
    assert diff_path.read_bytes() == different_data, 'A differing tenant config was modified'
    assert diff_path.stat().st_ino == diff_inode, 'A differing tenant config was replaced'


def test_rotate_script_exists_and_works():
    rotate_script = HOME / 'rotate.sh'
    assert rotate_script.is_file(), f'Missing rotate script at {rotate_script}'
    assert os.access(rotate_script, os.X_OK), f'Script {rotate_script} is not executable'

    # Stop the image's writer so a dedicated signal-aware process can make the
    # rotation contents deterministic.
    try:
        old_pid = int((LOGS / 'billing.pid').read_text().strip())
        if old_pid > 1:
            os.kill(old_pid, signal.SIGTERM)
    except (OSError, ValueError):
        pass
    time.sleep(0.8)

    helper_source = Path('/tmp/rotation_signal_helper.py')
    ready = Path('/tmp/rotation_signal_ready')
    signaled = Path('/tmp/rotation_signal_received')
    ready.unlink(missing_ok=True)
    signaled.unlink(missing_ok=True)
    helper_source.write_text(
        "import os, signal, time\n"
        "from pathlib import Path\n"
        "log=Path('/home/user/logs/billing.log')\n"
        "mark=Path('/tmp/rotation_signal_received')\n"
        "def h(sig, frame):\n"
        "    log.write_text('Log reopened\\n')\n"
        "    mark.write_text('yes')\n"
        "signal.signal(signal.SIGUSR1, h)\n"
        "Path('/tmp/rotation_signal_ready').write_text('ready')\n"
        "while True: time.sleep(0.1)\n"
    )
    helper = subprocess.Popen(['python3', str(helper_source)])
    try:
        assert wait_for(ready.exists), 'Signal test helper did not start'
        (LOGS / 'billing.pid').write_text(str(helper.pid) + '\n')

        markers = {
            'billing.log': 'CURRENT-' + uuid.uuid4().hex,
            'billing.log.1': 'OLD1-' + uuid.uuid4().hex,
            'billing.log.2': 'OLD2-' + uuid.uuid4().hex,
            'billing.log.3': 'OLD3-' + uuid.uuid4().hex,
        }
        for name, marker in markers.items():
            (LOGS / name).write_text(marker + '\n')
        (LOGS / 'billing.log.4').unlink(missing_ok=True)

        result = subprocess.run([str(rotate_script)], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f'Execution of {rotate_script} failed: {result.stderr}'
        assert wait_for(signaled.exists), 'The process in billing.pid did not receive SIGUSR1'
        assert wait_for(lambda: (LOGS / 'billing.log').is_file()), 'Current billing.log was not reopened'

        assert (LOGS / 'billing.log.1').is_file(), 'billing.log.1 was not created'
        assert (LOGS / 'billing.log.1').read_text() == markers['billing.log'] + '\n'
        assert (LOGS / 'billing.log.2').read_text() == markers['billing.log.1'] + '\n'
        assert (LOGS / 'billing.log.3').read_text() == markers['billing.log.2'] + '\n'
        assert not (LOGS / 'billing.log.4').exists(), 'Rotation retained more than three old logs'
        assert markers['billing.log.3'] not in ''.join(
            p.read_text() for p in LOGS.glob('billing.log*') if p.is_file()
        ), 'The oldest fourth-generation log was not discarded'
        assert 'Log reopened' in (LOGS / 'billing.log').read_text(), 'The billing process did not reopen its log'
    finally:
        helper.terminate()
        try:
            helper.wait(timeout=2)
        except subprocess.TimeoutExpired:
            helper.kill()
            helper.wait()


def run_monitor_case(binary, target, size_arg, duration, expect_invocation, probe_file):
    probe_file.unlink(missing_ok=True)
    proc = subprocess.Popen(
        [str(binary), str(target), str(size_arg)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        if expect_invocation:
            assert wait_for(probe_file.exists, duration), f'{binary} did not invoke rotate.sh for an oversized file'
        else:
            time.sleep(duration)
            assert not probe_file.exists(), f'{binary} invoked rotate.sh when the size did not strictly exceed the limit'
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


def test_monitor_c_compiled_and_behavior():
    monitor_c = HOME / 'monitor.c'
    monitor_bin = HOME / 'monitor'
    assert monitor_c.is_file(), f'Source file {monitor_c} is missing'
    assert monitor_bin.is_file(), f'Compiled binary {monitor_bin} is missing'
    assert os.access(monitor_bin, os.X_OK), f'Compiled binary {monitor_bin} is not executable'
    assert monitor_bin.read_bytes()[:4] == b'\x7fELF', 'monitor is not a compiled executable binary'

    rebuilt = Path('/tmp/monitor_rebuilt')
    compile_result = subprocess.run(
        ['gcc', str(monitor_c), '-o', str(rebuilt)], capture_output=True, text=True, timeout=20
    )
    assert compile_result.returncode == 0, f'monitor.c does not compile: {compile_result.stderr}'

    for binary in (monitor_bin, rebuilt):
        for args in ([], ['/tmp/a', '1', 'extra']):
            try:
                result = subprocess.run([str(binary), *args], capture_output=True, timeout=2)
            except subprocess.TimeoutExpired:
                pytest.fail(f'{binary} did not reject an invalid argument count')
            assert result.returncode != 0, f'{binary} accepted an invalid argument count'

    rotate = HOME / 'rotate.sh'
    saved_rotate = Path('/tmp/rotate.sh.saved')
    saved_rotate.write_bytes(rotate.read_bytes())
    saved_mode = rotate.stat().st_mode
    probe = Path('/tmp/monitor_rotation_probe_' + uuid.uuid4().hex)
    rotate.write_text(f'#!/bin/bash\necho invoked >> {probe}\n')
    rotate.chmod(0o755)

    target = Path('/tmp/monitor_target_' + uuid.uuid4().hex)
    target.write_bytes(os.urandom(257))
    try:
        for binary in (monitor_bin, rebuilt):
            run_monitor_case(binary, target, 257, 1.3, False, probe)
            run_monitor_case(binary, target, 256, 2.5, True, probe)

        missing = Path('/tmp/missing_monitor_target_' + uuid.uuid4().hex)
        probe.unlink(missing_ok=True)
        proc = subprocess.Popen(
            [str(monitor_bin), str(missing), '1'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        time.sleep(1.2)
        assert not probe.exists(), 'monitor invoked rotation for a missing file'
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=2)
        else:
            assert proc.returncode != 0, 'monitor silently succeeded after a file lookup error'
    finally:
        rotate.write_bytes(saved_rotate.read_bytes())
        rotate.chmod(saved_mode & 0o7777)
        probe.unlink(missing_ok=True)
        target.unlink(missing_ok=True)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
