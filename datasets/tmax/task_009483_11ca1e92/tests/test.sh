#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import math
import os
import secrets
import subprocess
import sys
import tarfile
import zipfile


def test_extracted_data_dir():
    extract_dir = "/home/user/extracted_data"
    assert os.path.exists(extract_dir), f"Directory {extract_dir} does not exist."
    assert os.path.isdir(extract_dir), f"{extract_dir} should be a directory."

    expected_files = {"chunk1.tar.gz", "chunk2.tar.gz", "chunk3.tar.gz"}
    actual_files = set(os.listdir(extract_dir))
    for expected in expected_files:
        assert expected in actual_files, f"Expected {expected} to be extracted to {extract_dir}."

    # The extracted files must be the actual archives from the supplied zip,
    # rather than empty placeholders with the expected names.
    with zipfile.ZipFile("/home/user/research_data.zip", "r") as source_zip:
        for expected in expected_files:
            extracted_path = os.path.join(extract_dir, expected)
            assert os.path.isfile(extracted_path)
            with source_zip.open(expected, "r") as source_file:
                assert open(extracted_path, "rb").read() == source_file.read()
            assert tarfile.is_tarfile(extracted_path), f"{extracted_path} is not a valid tar archive."


def test_aggregator_script():
    script_path = "/home/user/aggregator.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} should be a file."

    with open(script_path, "r") as f:
        content = f.read()

    assert "fcntl.flock" in content, "The script must use fcntl.flock to acquire an exclusive lock."


def test_results_csv():
    results_path = "/home/user/results.csv"
    assert os.path.exists(results_path), f"Results file {results_path} does not exist."
    assert os.path.isfile(results_path), f"{results_path} should be a file."

    with open(results_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = {
        "alpha,60.0",
        "beta,31.0",
        "gamma,50.0"
    }

    assert set(lines) == expected_lines, f"Expected {expected_lines} in {results_path}, but got {set(lines)}."
    assert len(lines) == 3, f"Expected exactly 3 lines in {results_path}, but got {len(lines)}."


def _make_archive(path, sensor_id, readings):
    metadata = json.dumps({"sensor_id": sensor_id}).encode("utf-8")
    csv_text = "sequence,reading,status\n" + "".join(
        f"{i},{value},ok\n" for i, value in enumerate(readings)
    )
    data = csv_text.encode("utf-8")

    with tarfile.open(path, "w:gz") as archive:
        metadata_info = tarfile.TarInfo("metadata.json")
        metadata_info.size = len(metadata)
        archive.addfile(metadata_info, io.BytesIO(metadata))

        data_info = tarfile.TarInfo("data.csv")
        data_info.size = len(data)
        archive.addfile(data_info, io.BytesIO(data))


def test_aggregator_executes_and_locks_concurrent_writes(tmp_path):
    results_path = "/home/user/results.csv"
    script_path = "/home/user/aggregator.py"
    os.remove(results_path)

    monitor_dir = tmp_path / "monitor"
    monitor_dir.mkdir()
    sitecustomize = r'''
import builtins
import fcntl
import io
import os
import time

_RESULTS = "/home/user/results.csv"
_MARKER = os.environ["FLOCK_MARKER"]
_locked = set()
_real_flock = fcntl.flock
_real_open = builtins.open
_real_io_open = io.open
_real_os_open = os.open
_real_os_write = os.write


def _fd(value):
    return value if isinstance(value, int) else value.fileno()


def _is_results_fd(fd):
    try:
        return os.path.realpath(f"/proc/self/fd/{fd}") == _RESULTS
    except OSError:
        return False


def checked_flock(file_or_fd, operation):
    fd = _fd(file_or_fd)
    result = _real_flock(file_or_fd, operation)
    if _is_results_fd(fd):
        if operation & fcntl.LOCK_EX:
            _locked.add(fd)
            marker_fd = _real_os_open(_MARKER, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            _real_os_write(marker_fd, b"exclusive lock acquired")
            os.close(marker_fd)
            # Hold the acquired lock briefly so concurrently started workers
            # genuinely contend on it.
            time.sleep(0.05)
        if operation & fcntl.LOCK_UN:
            _locked.discard(fd)
    return result


class GuardedFile:
    def __init__(self, wrapped):
        self._wrapped = wrapped
    def fileno(self):
        return self._wrapped.fileno()
    def write(self, value):
        if self.fileno() not in _locked:
            raise RuntimeError("results.csv was written without an exclusive flock")
        return self._wrapped.write(value)
    def writelines(self, values):
        if self.fileno() not in _locked:
            raise RuntimeError("results.csv was written without an exclusive flock")
        return self._wrapped.writelines(values)
    def __enter__(self):
        self._wrapped.__enter__()
        return self
    def __exit__(self, *args):
        return self._wrapped.__exit__(*args)
    def __iter__(self):
        return iter(self._wrapped)
    def __getattr__(self, name):
        return getattr(self._wrapped, name)


def _checked_file_open(real_open, file, mode="r", *args, **kwargs):
    path = os.path.realpath(os.fspath(file)) if not isinstance(file, int) else None
    writable = any(ch in mode for ch in "wax+")
    if path == _RESULTS and writable:
        if "a" not in mode:
            raise RuntimeError("results.csv must be opened in append mode")
        return GuardedFile(real_open(file, mode, *args, **kwargs))
    return real_open(file, mode, *args, **kwargs)


def checked_open(file, mode="r", *args, **kwargs):
    return _checked_file_open(_real_open, file, mode, *args, **kwargs)


def checked_io_open(file, mode="r", *args, **kwargs):
    return _checked_file_open(_real_io_open, file, mode, *args, **kwargs)


def checked_os_open(path, flags, *args, **kwargs):
    if os.path.realpath(os.fspath(path)) == _RESULTS and flags & (os.O_WRONLY | os.O_RDWR):
        if not flags & os.O_APPEND:
            raise RuntimeError("results.csv must be opened with O_APPEND")
    return _real_os_open(path, flags, *args, **kwargs)


def checked_os_write(fd, data):
    if _is_results_fd(fd) and fd not in _locked:
        raise RuntimeError("results.csv was written without an exclusive flock")
    return _real_os_write(fd, data)


fcntl.flock = checked_flock
builtins.open = checked_open
io.open = checked_io_open
os.open = checked_os_open
os.write = checked_os_write
'''
    (monitor_dir / "sitecustomize.py").write_text(sitecustomize)

    expected = {}
    archive_paths = []
    for index in range(12):
        sensor_id = f"runtime_{secrets.token_hex(8)}_{index}"
        readings = [
            index + 0.25,
            -(index / 2.0),
            (index * 3) + 1.5,
            7.0,
        ]
        archive_path = tmp_path / f"input_{index}.tar.gz"
        _make_archive(archive_path, sensor_id, readings)
        expected[sensor_id] = sum(readings)
        archive_paths.append(archive_path)

    processes = []
    for index, archive_path in enumerate(archive_paths):
        marker = tmp_path / f"lock_{index}.marker"
        env = os.environ.copy()
        env["PYTHONPATH"] = str(monitor_dir)
        env["FLOCK_MARKER"] = str(marker)
        process = subprocess.Popen(
            [sys.executable, "-c", "import runpy; runpy.run_path('/home/user/aggregator.py', run_name='__main__')"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
        )
        process.stdin.write((str(archive_path) + "\n").encode("utf-8"))
        process.stdin.close()
        processes.append((process, marker))

    failures = []
    for process, marker in processes:
        try:
            return_code = process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            return_code = process.wait()
            failures.append("worker timed out")
        stdout = process.stdout.read().decode("utf-8", "replace")
        stderr = process.stderr.read().decode("utf-8", "replace")
        if return_code != 0:
            failures.append(f"worker exited {return_code}; stdout={stdout!r}; stderr={stderr!r}")
        assert marker.exists(), "A worker did not acquire an exclusive flock on results.csv."

    assert not failures, "\n".join(failures)
    assert os.path.isfile(results_path)

    with open(results_path, newline="") as result_file:
        rows = list(csv.reader(result_file))

    assert len(rows) == len(expected), f"Expected {len(expected)} result rows, got {len(rows)}: {rows!r}"
    observed = {}
    for row in rows:
        assert len(row) == 2, f"Malformed result row: {row!r}"
        sensor_id, total = row
        assert sensor_id not in observed, f"Duplicate result for {sensor_id}"
        observed[sensor_id] = float(total)

    assert set(observed) == set(expected)
    for sensor_id, expected_total in expected.items():
        assert math.isclose(observed[sensor_id], expected_total, rel_tol=1e-12, abs_tol=1e-12)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
