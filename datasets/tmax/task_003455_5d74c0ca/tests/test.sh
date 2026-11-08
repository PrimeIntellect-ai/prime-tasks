#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import struct
import subprocess
import tempfile
from pathlib import Path

PROJECT = Path('/home/user/project')
DATA = PROJECT / 'data'
PY_WORKER = PROJECT / 'py_worker.py'
ORCHESTRATOR = PROJECT / 'test_orchestrator.py'
LINUX_BINARY = PROJECT / 'build/linux/worker'
WINDOWS_BINARY = PROJECT / 'build/windows/worker.exe'
RESULT_LOG = PROJECT / 'test_result.log'


def expected_word_count(directory=DATA):
    total = 0
    for entry in directory.iterdir():
        if entry.is_file() and entry.name.endswith('.txt'):
            total += len(entry.read_text().split())
    return total


def exact_output(count):
    return f'Total words: {count}\n'


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, timeout=180, **kwargs)


def assert_linux_amd64(path):
    data = path.read_bytes()
    assert data[:4] == b'\x7fELF', 'Linux worker is not an ELF binary'
    assert len(data) >= 20 and data[4] == 2, 'Linux worker is not a 64-bit ELF binary'
    byteorder = 'little' if data[5] == 1 else 'big'
    assert int.from_bytes(data[18:20], byteorder) == 62, 'Linux worker is not an amd64 ELF binary'


def assert_windows_amd64(path):
    data = path.read_bytes()
    assert data[:2] == b'MZ', 'Windows worker is not a PE executable'
    assert len(data) >= 64, 'Windows executable is truncated'
    pe_offset = struct.unpack_from('<I', data, 0x3c)[0]
    assert data[pe_offset:pe_offset + 4] == b'PE\0\0', 'Windows worker lacks a PE header'
    machine = struct.unpack_from('<H', data, pe_offset + 4)[0]
    assert machine == 0x8664, 'Windows worker is not amd64'


def assert_artifacts(expected_count):
    assert LINUX_BINARY.is_file(), f'Linux binary is missing: {LINUX_BINARY}'
    assert os.stat(LINUX_BINARY).st_mode & stat.S_IXUSR, 'Linux binary is not executable'
    assert WINDOWS_BINARY.is_file(), f'Windows binary is missing: {WINDOWS_BINARY}'
    assert_linux_amd64(LINUX_BINARY)
    assert_windows_amd64(WINDOWS_BINARY)

    result = run([str(LINUX_BINARY), str(DATA)])
    assert result.returncode == 0, f'Linux worker failed: {result.stderr}'
    assert result.stdout == exact_output(expected_count), repr(result.stdout)


def install_concurrency_probe(directory, event_file):
    source = r'''
import os
import queue
import concurrent.futures
import multiprocessing.pool

_EVENT_FILE = os.environ.get('WORKER_PROBE_EVENTS')
def _log(event):
    if _EVENT_FILE:
        with open(_EVENT_FILE, 'a') as stream:
            stream.write(event + '\n')

_Queue = queue.Queue
class ProbedQueue(_Queue):
    def __init__(self, *args, **kwargs):
        _log('queue_init')
        super().__init__(*args, **kwargs)
    def put(self, *args, **kwargs):
        _log('queue_put')
        return super().put(*args, **kwargs)
    def get(self, *args, **kwargs):
        _log('queue_get')
        return super().get(*args, **kwargs)
queue.Queue = ProbedQueue

_Executor = concurrent.futures.ThreadPoolExecutor
class ProbedExecutor(_Executor):
    def __init__(self, *args, **kwargs):
        _log('pool_init')
        super().__init__(*args, **kwargs)
    def submit(self, *args, **kwargs):
        _log('pool_task')
        return super().submit(*args, **kwargs)
concurrent.futures.ThreadPoolExecutor = ProbedExecutor

_MPThreadPool = multiprocessing.pool.ThreadPool
class ProbedMPThreadPool(_MPThreadPool):
    def __init__(self, *args, **kwargs):
        _log('pool_init')
        super().__init__(*args, **kwargs)
    def apply(self, *args, **kwargs):
        _log('pool_task')
        return super().apply(*args, **kwargs)
    def apply_async(self, *args, **kwargs):
        _log('pool_task')
        return super().apply_async(*args, **kwargs)
    def map(self, *args, **kwargs):
        _log('pool_task')
        return super().map(*args, **kwargs)
    def imap(self, *args, **kwargs):
        _log('pool_task')
        return super().imap(*args, **kwargs)
    def imap_unordered(self, *args, **kwargs):
        _log('pool_task')
        return super().imap_unordered(*args, **kwargs)
multiprocessing.pool.ThreadPool = ProbedMPThreadPool
'''
    (directory / 'sitecustomize.py').write_text(source)


def test_complete_project():
    # Preserve the original final-state assertions before rebuilding anything.
    assert PY_WORKER.is_file(), f'Python worker script is missing: {PY_WORKER}'
    assert ORCHESTRATOR.is_file(), f'Test orchestrator script is missing: {ORCHESTRATOR}'
    assert LINUX_BINARY.is_file(), f'Linux binary is missing: {LINUX_BINARY}'
    assert WINDOWS_BINARY.is_file(), f'Windows binary is missing: {WINDOWS_BINARY}'
    assert RESULT_LOG.is_file(), f'Test result log is missing: {RESULT_LOG}'

    initial_count = expected_word_count()
    assert RESULT_LOG.read_text().strip() == f'TEST PASSED: Total words: {initial_count}'
    initial_py = run(['python3', str(PY_WORKER), str(DATA)])
    assert initial_py.returncode == 0, initial_py.stderr
    assert initial_py.stdout == exact_output(initial_count), repr(initial_py.stdout)
    assert_artifacts(initial_count)

    # Exercise the Python worker on verifier-created input while observing actual
    # construction and use of both a thread pool and a queue.
    with tempfile.TemporaryDirectory() as td, tempfile.TemporaryDirectory() as pd:
        test_data = Path(td)
        probe_dir = Path(pd)
        (test_data / 'one.txt').write_text('alpha beta\ngamma')
        (test_data / 'two.txt').write_text('four\tfive six seven')
        (test_data / 'ignored.bin').write_text('these words must not count')
        (test_data / 'also_ignored.TXT').write_text('not counted')
        events = probe_dir / 'events.log'
        install_concurrency_probe(probe_dir, events)
        env = os.environ.copy()
        env['WORKER_PROBE_EVENTS'] = str(events)
        env['PYTHONPATH'] = str(probe_dir) + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
        result = run(['python3', str(PY_WORKER), str(test_data)], env=env)
        assert result.returncode == 0, result.stderr
        assert result.stdout == exact_output(7), repr(result.stdout)
        observed = events.read_text().splitlines() if events.exists() else []
        assert 'pool_init' in observed, 'py_worker.py did not create a thread pool'
        assert 'pool_task' in observed, 'py_worker.py did not submit work to its thread pool'
        assert 'queue_init' in observed, 'py_worker.py did not create a queue'
        assert 'queue_put' in observed and 'queue_get' in observed, 'py_worker.py did not pass work/results through a queue'

    # Make the project data unpredictable, then require the orchestrator to
    # recreate both binaries through real GOOS/GOARCH go-build invocations.
    challenge = DATA / f'verifier_{os.getpid()}.txt'
    challenge.write_text('dynamic verifier words\nwith several more tokens')
    original_worker = PY_WORKER.read_bytes()
    original_mode = stat.S_IMODE(PY_WORKER.stat().st_mode)

    with tempfile.TemporaryDirectory() as wd:
        wrapper_dir = Path(wd)
        go_log = wrapper_dir / 'go_calls.log'
        real_go = shutil.which('go')
        assert real_go, 'go compiler is unavailable'
        wrapper = wrapper_dir / 'go'
        wrapper.write_text(f'''#!/bin/bash\nprintf '%s|%s|%s\\n' "$GOOS" "$GOARCH" "$*" >> {str(go_log)!r}\nexec {real_go!r} "$@"\n''')
        wrapper.chmod(0o755)
        env = os.environ.copy()
        env['PATH'] = str(wrapper_dir) + os.pathsep + env['PATH']

        def execute_orchestrator():
            shutil.rmtree(PROJECT / 'build', ignore_errors=True)
            if RESULT_LOG.exists():
                RESULT_LOG.unlink()
            if go_log.exists():
                go_log.unlink()
            result = run(['python3', str(ORCHESTRATOR)], cwd=str(PROJECT), env=env)
            calls = go_log.read_text().splitlines() if go_log.exists() else []
            assert any(line.startswith('linux|amd64|') and 'build' in line and 'worker.go' in line for line in calls), \
                f'orchestrator did not invoke go build for linux/amd64: {calls}'
            assert any(line.startswith('windows|amd64|') and 'build' in line and 'worker.go' in line for line in calls), \
                f'orchestrator did not invoke go build for windows/amd64: {calls}'
            return result

        try:
            count = expected_word_count()
            success = execute_orchestrator()
            assert success.returncode == 0, success.stderr
            assert_artifacts(count)
            assert RESULT_LOG.is_file(), 'orchestrator did not generate test_result.log'
            assert RESULT_LOG.read_text().strip() == f'TEST PASSED: Total words: {count}'

            # Force the two implementations to disagree. The orchestrator must
            # perform the comparison and replace the log with exactly TEST FAILED.
            PY_WORKER.write_text("print('Total words: -123456')\n")
            PY_WORKER.chmod(original_mode)
            execute_orchestrator()
            assert RESULT_LOG.is_file(), 'orchestrator did not log a failed comparison'
            assert RESULT_LOG.read_text().strip() == 'TEST FAILED', RESULT_LOG.read_text()

            # Restore the submission and execute once more, leaving a valid final state.
            PY_WORKER.write_bytes(original_worker)
            PY_WORKER.chmod(original_mode)
            final = execute_orchestrator()
            assert final.returncode == 0, final.stderr
            final_count = expected_word_count()
            assert_artifacts(final_count)
            assert RESULT_LOG.read_text().strip() == f'TEST PASSED: Total words: {final_count}'
        finally:
            PY_WORKER.write_bytes(original_worker)
            PY_WORKER.chmod(original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
