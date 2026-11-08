#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import time
import uuid
import signal
import subprocess
from pathlib import Path

BASE = Path('/home/user/deploy')
SRC = BASE / 'src/processor.cpp'
BIN = BASE / 'bin/processor'
MONITOR = BASE / 'scripts/monitor.sh'
SUMMARY = BASE / 'scripts/summary.sh'
PIDFILE = BASE / 'run/daemon.pid'
LOG = BASE / 'logs/system.log'
IN_DIR = BASE / 'data/in'
OUT_DIR = BASE / 'data/out'


def read_pid():
    try:
        text = PIDFILE.read_text().strip()
        return int(text) if text.isdigit() else None
    except (OSError, ValueError):
        return None


def alive(pid):
    if not pid:
        return False
    try:
        os.kill(pid, 0)
        stat_text = Path(f'/proc/{pid}/stat').read_text()
        return stat_text.split()[2] != 'Z'
    except (OSError, IndexError):
        return False


def exe_is_processor(pid):
    try:
        return Path(f'/proc/{pid}/exe').resolve() == BIN.resolve()
    except OSError:
        return False


def wait_for(predicate, timeout=10, interval=0.1):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(interval)
    return None


def stop_deployment_processes():
    targets = []
    me = os.getpid()
    for item in Path('/proc').iterdir():
        if not item.name.isdigit() or int(item.name) == me:
            continue
        pid = int(item.name)
        try:
            cmdline = (item / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='ignore')
            exe = (item / 'exe').resolve()
        except OSError:
            continue
        if str(MONITOR) in cmdline or exe == BIN.resolve():
            targets.append(pid)
    for pid in targets:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
    time.sleep(0.5)
    for pid in targets:
        if alive(pid):
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass


def reset_runtime():
    stop_deployment_processes()
    IN_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for directory in (IN_DIR, OUT_DIR):
        for path in directory.iterdir():
            if path.is_file() or path.is_symlink():
                path.unlink()
    LOG.parent.mkdir(parents=True, exist_ok=True)
    LOG.write_text('')
    try:
        PIDFILE.unlink()
    except FileNotFoundError:
        pass


def test_summary_result():
    result_file = BASE / 'summary_result.txt'
    assert result_file.is_file(), f'Verification file missing: {result_file}'
    assert result_file.read_text().strip() == '4', 'Expected summary_result.txt to contain 4'


def test_monitor_script_executable():
    assert MONITOR.is_file(), f'Monitor script missing: {MONITOR}'
    assert bool(MONITOR.stat().st_mode & stat.S_IXUSR), f'Monitor script is not executable: {MONITOR}'


def test_summary_script_executable():
    assert SUMMARY.is_file(), f'Summary script missing: {SUMMARY}'
    assert bool(SUMMARY.stat().st_mode & stat.S_IXUSR), f'Summary script is not executable: {SUMMARY}'


def test_processed_files():
    assert OUT_DIR.is_dir(), f'Output directory missing: {OUT_DIR}'
    files = [p for p in OUT_DIR.iterdir() if p.is_file()]
    assert len(files) >= 4, f'Expected at least 4 processed files in {OUT_DIR}, found {len(files)}'


def test_cpp_code_fixed():
    assert SRC.is_file(), f'Source file missing: {SRC}'
    content = SRC.read_text()
    assert 'std::abort()' not in content, 'The C++ code still contains std::abort() which causes crashes.'
    assert 'WARNING: Poison pill skipped in' in content, 'The C++ code does not log the expected warning message.'


def test_binary_and_initial_live_state():
    assert BIN.is_file(), f'Compiled processor missing: {BIN}'
    assert os.access(BIN, os.X_OK), f'Compiled processor is not executable: {BIN}'
    assert BIN.read_bytes()[:4] == b'\x7fELF', 'processor is not a compiled ELF executable'

    def live_recorded_processor():
        pid = read_pid()
        return pid if alive(pid) and exe_is_processor(pid) else None

    pid = wait_for(live_recorded_processor, timeout=6)
    assert pid, 'No live processor was recorded in daemon.pid before verification'
    assert LOG.is_file() and 'HEARTBEAT' in LOG.read_text(errors='replace'), 'The running daemon has not logged a heartbeat'


def exercise_processor(executable):
    reset_runtime()
    token = uuid.uuid4().hex
    normal = {
        f'alpha_{token}.txt': f'alpha {token}\n',
        f'beta_{token}.txt': f'beta {token}\n',
        f'gamma_{token}.txt': f'gamma {token}\n',
    }
    poison_name = f'poison_{token}.txt'
    for name, content in normal.items():
        (IN_DIR / name).write_text(content)
    (IN_DIR / poison_name).write_text(f'prefix POISON_PILL suffix {token}\n')

    stderr_path = Path(f'/tmp/processor-stderr-{token}')
    with stderr_path.open('wb') as err:
        proc = subprocess.Popen([str(executable)], stdout=subprocess.DEVNULL, stderr=err)
        try:
            def completed():
                return all((OUT_DIR / name).is_file() for name in normal)
            assert wait_for(completed, timeout=8), f'{executable} did not process all normal files'
            assert proc.poll() is None, f'{executable} died after encountering the poison file'
            time.sleep(0.3)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=3)

    for name, content in normal.items():
        assert (OUT_DIR / name).read_text() == content + ' PROCESSED', f'Incorrect output for {name}'
        assert not (IN_DIR / name).exists(), f'Processed input was not removed: {name}'
    assert (IN_DIR / poison_name).is_file(), 'Poison input should be skipped rather than processed or removed'
    assert not (OUT_DIR / poison_name).exists(), 'Poison input incorrectly produced an output file'

    stderr = stderr_path.read_text(errors='replace')
    assert f'WARNING: Poison pill skipped in {poison_name}' in stderr, 'Expected poison warning was not written to standard error'
    log_text = LOG.read_text(errors='replace')
    assert 'HEARTBEAT' in log_text, 'Processor did not log a heartbeat'
    for name in normal:
        assert f'SUCCESS: Processed {name}' in log_text, f'Missing success log for {name}'


def test_processor_source_and_submitted_binary_behavior():
    candidate = Path('/tmp/processor-from-submitted-source')
    result = subprocess.run(
        ['g++', '-std=c++17', str(SRC), '-o', str(candidate)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f'processor.cpp does not compile with g++ -std=c++17:\n{result.stderr}'
    exercise_processor(BIN)
    exercise_processor(candidate)


def test_summary_script_behavior():
    with LOG.open('a') as log:
        log.write('NOTSUCCESS: Processed decoy.txt\n')
        log.write('SUCCESS: Failed decoy.txt\n')
        log.write('SUCCESS: Processed synthetic.txt\n')
    lines = LOG.read_text(errors='replace').splitlines()
    expected = sum(1 for line in lines if re.fullmatch(r'SUCCESS: Processed .+', line))
    result = subprocess.run([str(SUMMARY)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5)
    assert result.returncode == 0, f'summary.sh failed: {result.stderr}'
    assert re.fullmatch(r'\s*\d+\s*', result.stdout), 'summary.sh must output only an integer'
    assert int(result.stdout.strip()) == expected, f'summary.sh returned {result.stdout.strip()}, expected {expected}'


def test_monitor_restarts_dead_daemon_and_updates_pidfile():
    reset_runtime()
    token = uuid.uuid4().hex
    name = f'monitor_{token}.txt'
    (IN_DIR / name).write_text(f'monitor data {token}\n')
    monitor_out = open('/tmp/monitor-test-output', 'wb')
    monitor = subprocess.Popen([str(MONITOR)], stdout=monitor_out, stderr=monitor_out, start_new_session=True)
    try:
        def first_daemon():
            pid = read_pid()
            return pid if alive(pid) and exe_is_processor(pid) else None
        first = wait_for(first_daemon, timeout=8)
        assert first, 'monitor.sh did not start the processor and record its PID'
        assert wait_for(lambda: (OUT_DIR / name).is_file(), timeout=6), 'Daemon started by monitor did not process input'
        assert wait_for(lambda: LOG.is_file() and 'HEARTBEAT' in LOG.read_text(errors='replace'), timeout=6), 'Monitored daemon did not log a heartbeat'
        heartbeat_count = LOG.read_text(errors='replace').count('HEARTBEAT')

        os.kill(first, signal.SIGKILL)
        def replacement():
            pid = read_pid()
            return pid if pid and pid != first and alive(pid) and exe_is_processor(pid) else None
        second = wait_for(replacement, timeout=10)
        assert second, 'monitor.sh did not restart the dead daemon or update daemon.pid'
        assert monitor.poll() is None, 'monitor.sh exited instead of continuing its monitoring loop'
        assert wait_for(lambda: LOG.read_text(errors='replace').count('HEARTBEAT') > heartbeat_count, timeout=5), 'Restarted daemon did not resume heartbeats'
    finally:
        try:
            os.killpg(monitor.pid, signal.SIGTERM)
        except OSError:
            pass
        try:
            monitor.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(monitor.pid, signal.SIGKILL)
            except OSError:
                pass
        monitor_out.close()
        stop_deployment_processes()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
