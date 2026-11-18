#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import io
import os
import pathlib
import secrets
import stat
import subprocess
import tarfile
import time
import uuid
import zipfile

import pytest

SCRIPT_PATH = "/home/user/aggregate.py"
CONFIG_PATH = "/home/user/config.ini"
DATASET_PATH = "/home/user/dataset.tar.gz"
LOG_PATH = "/home/user/summary.log"


def test_01_aggregate_script_exists_and_uses_flock():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert stat.S_ISREG(os.stat(script_path).st_mode), f"Script {script_path} is not a regular file."

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "fcntl" in content, "The script does not import or use fcntl."
    assert "flock" in content, "The script does not use fcntl.flock."
    assert "LOCK_EX" in content, "The script does not use LOCK_EX for exclusive locking."


def test_02_summary_log_exists_and_correct():
    log_path = LOG_PATH
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run the script?"

    with open(log_path, "r") as f:
        lines = f.read().splitlines()

    expected_line = "experiment_B.zip/sensor_readings.csv SUM:400"

    # Preserve the original assertion that the requested initial execution occurred.
    assert any(expected_line in line for line in lines), \
        f"Expected '{expected_line}' to be in {log_path}, but it was not found. Contents: {lines}"


def make_dataset(zip_name, csv_name, rows):
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as nested_zip:
        csv_data = "".join(f"row{i},{value}\n" for i, value in enumerate(rows))
        nested_zip.writestr(csv_name, csv_data)
        nested_zip.writestr("irrelevant.csv", "x,999999\n")

    decoy_buffer = io.BytesIO()
    with zipfile.ZipFile(decoy_buffer, "w", zipfile.ZIP_DEFLATED) as decoy_zip:
        decoy_zip.writestr("decoy.csv", "x,888888\n")

    tar_buffer = io.BytesIO()
    with tarfile.open(fileobj=tar_buffer, mode="w:gz") as outer_tar:
        for archive_name, archive_data in [
            ("decoy.zip", decoy_buffer.getvalue()),
            (zip_name, zip_buffer.getvalue()),
        ]:
            info = tarfile.TarInfo(archive_name)
            info.size = len(archive_data)
            outer_tar.addfile(info, io.BytesIO(archive_data))
    return tar_buffer.getvalue()


def save_paths(paths):
    saved = {}
    for path in paths:
        if os.path.lexists(path):
            saved[path] = (True, pathlib.Path(path).read_bytes(), os.stat(path).st_mode)
        else:
            saved[path] = (False, b"", 0)
    return saved


def restore_paths(saved):
    for path, (existed, data, mode) in saved.items():
        if os.path.lexists(path):
            os.unlink(path)
        if existed:
            pathlib.Path(path).write_bytes(data)
            os.chmod(path, stat.S_IMODE(mode))


def install_case(zip_name, csv_name, values):
    pathlib.Path(CONFIG_PATH).write_text(
        f"[Target]\nzip_file = {zip_name}\ncsv_file = {csv_name}\n"
    )
    pathlib.Path(DATASET_PATH).write_bytes(make_dataset(zip_name, csv_name, values))
    if os.path.lexists(LOG_PATH):
        os.unlink(LOG_PATH)


def run_script(timeout=8):
    return subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def test_03_executes_script_and_derives_results_from_archives_and_config():
    paths = [CONFIG_PATH, DATASET_PATH, LOG_PATH]
    saved = save_paths(paths)
    try:
        rng = secrets.SystemRandom()
        for _ in range(2):
            token = uuid.uuid4().hex
            zip_name = f"experiment_{token}.zip"
            csv_name = f"measurements_{token}.csv"
            values = [rng.randint(-5000, 5000) for _ in range(rng.randint(3, 8))]
            install_case(zip_name, csv_name, values)

            result = run_script()
            assert result.returncode == 0, \
                f"aggregate.py failed. stdout={result.stdout!r}, stderr={result.stderr!r}"
            assert os.path.isfile(LOG_PATH), "aggregate.py did not create summary.log"

            lines = pathlib.Path(LOG_PATH).read_text().splitlines()
            expected = f"{zip_name}/{csv_name} SUM:{sum(values)}"
            assert lines == [expected], f"Expected exactly {expected!r}, got {lines!r}"
    finally:
        restore_paths(saved)


def test_04_exclusive_flock_is_acquired_before_appending():
    paths = [CONFIG_PATH, DATASET_PATH, LOG_PATH]
    saved = save_paths(paths)
    proc = None
    lock_file = None
    try:
        token = uuid.uuid4().hex
        zip_name = f"locked_{token}.zip"
        csv_name = f"locked_data_{token}.csv"
        values = [17, -3, 41, 9]
        install_case(zip_name, csv_name, values)

        # Hold the exact log inode under an exclusive lock. A correct script must
        # open this file and block in flock before it can append anything.
        lock_file = open(LOG_PATH, "a+")
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        proc = subprocess.Popen(
            ["python3", SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        time.sleep(0.75)
        assert proc.poll() is None, \
            "aggregate.py completed while another process held summary.log's exclusive lock"
        assert os.path.getsize(LOG_PATH) == 0, \
            "aggregate.py appended before obtaining the exclusive lock"

        # While blocked, the child must actually have summary.log open.
        child_has_log = False
        fd_dir = f"/proc/{proc.pid}/fd"
        for fd in os.listdir(fd_dir):
            try:
                if os.path.samefile(os.path.join(fd_dir, fd), LOG_PATH):
                    child_has_log = True
                    break
            except (FileNotFoundError, OSError):
                pass
        assert child_has_log, "aggregate.py did not open summary.log while waiting for its lock"

        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        lock_file.close()
        lock_file = None

        stdout, stderr = proc.communicate(timeout=8)
        assert proc.returncode == 0, \
            f"aggregate.py failed after lock release. stdout={stdout!r}, stderr={stderr!r}"
        expected = f"{zip_name}/{csv_name} SUM:{sum(values)}"
        assert pathlib.Path(LOG_PATH).read_text().splitlines() == [expected]
    finally:
        if lock_file is not None:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
            lock_file.close()
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.communicate()
        restore_paths(saved)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
