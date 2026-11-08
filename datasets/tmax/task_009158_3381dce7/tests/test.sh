#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
import time
from pathlib import Path

import pytest


def test_drop_directory_empty():
    """Verify that the drop directory is empty after processing."""
    drop_dir = '/home/user/storage_drop'
    assert os.path.exists(drop_dir), f"Directory {drop_dir} does not exist."
    assert os.path.isdir(drop_dir), f"{drop_dir} is not a directory."
    files = os.listdir(drop_dir)
    assert len(files) == 0, f"Drop directory is not empty. Found: {files}"


def test_processed_legacy_dump():
    """Verify that the first file was correctly processed, renamed, and encoded."""
    file_path = '/home/user/storage_archive/legacy_dump.txt.processed'
    assert os.path.exists(file_path), f"Processed file {file_path} does not exist."

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read().strip()
    except UnicodeDecodeError:
        pytest.fail(f"File {file_path} is not valid UTF-8.")

    expected_content = 'Voilà, testing storage'
    assert content == expected_content, f"Content mismatch in {file_path}. Expected '{expected_content}', got '{content}'."


def test_processed_new_server_events():
    """Verify that the second file was correctly processed, renamed, and encoded."""
    file_path = '/home/user/storage_archive/new_server_events.log.processed'
    assert os.path.exists(file_path), f"Processed file {file_path} does not exist."

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read().strip()
    except UnicodeDecodeError:
        pytest.fail(f"File {file_path} is not valid UTF-8.")

    expected_content = 'Café server crashed'
    assert content == expected_content, f"Content mismatch in {file_path}. Expected '{expected_content}', got '{content}'."


def test_final_state_log():
    """Verify that the final state log contains the names of the processed files."""
    log_file = '/home/user/final_state.log'
    assert os.path.exists(log_file), f"Log file {log_file} does not exist."

    with open(log_file, 'r', encoding='utf-8', errors='replace') as f:
        log_content = f.read()

    assert 'legacy_dump.txt.processed' in log_content, f"'legacy_dump.txt.processed' not found in {log_file}."
    assert 'new_server_events.log.processed' in log_content, f"'new_server_events.log.processed' not found in {log_file}."


def wait_for_processing(proc, source, destination, expected_text, timeout=8):
    deadline = time.monotonic() + timeout
    expected_bytes = expected_text.encode('utf-8')
    while time.monotonic() < deadline:
        if destination.is_file() and not source.exists():
            try:
                actual = destination.read_bytes()
            except OSError:
                actual = None
            if actual == expected_bytes:
                return
        if proc.poll() is not None:
            pytest.fail(f"storage_manager.py exited unexpectedly with status {proc.returncode}")
        time.sleep(0.1)

    actual = destination.read_bytes() if destination.is_file() else None
    pytest.fail(
        f"Timed out processing {source.name}; source_exists={source.exists()}, "
        f"destination_exists={destination.exists()}, destination_bytes={actual!r}"
    )


def test_storage_manager_dynamic_workflow(tmp_path):
    """Execute the submitted manager and test startup and ongoing processing."""
    script = Path('/home/user/storage_manager.py')
    assert script.exists(), f"{script} does not exist."
    assert not script.is_symlink(), f"{script} must be a submitted regular file, not a symlink."
    assert stat.S_ISREG(script.stat().st_mode), f"{script} is not a regular file."

    input_dir = tmp_path / 'random_input'
    output_dir = tmp_path / 'random_output'
    input_dir.mkdir()
    output_dir.mkdir()

    token = secrets.token_hex(6)
    startup_name = f'MiXeD Legacy {token}.TxT'
    startup_text = '€uro “startup” — déjà vu'
    startup_source = input_dir / startup_name
    startup_destination = output_dir / (startup_name.lower().replace(' ', '_') + '.processed')
    startup_source.write_bytes(startup_text.encode('cp1252'))

    proc = subprocess.Popen(
        ['python3', str(script), str(input_dir), str(output_dir)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        wait_for_processing(proc, startup_source, startup_destination, startup_text)

        incoming_name = f'NeW Server {token}.LoG'
        incoming_text = 'Café costs 10€ — “online”'
        incoming_source = input_dir / incoming_name
        incoming_destination = output_dir / (incoming_name.lower().replace(' ', '_') + '.processed')
        incoming_source.write_bytes(incoming_text.encode('cp1252'))
        wait_for_processing(proc, incoming_source, incoming_destination, incoming_text)

        time.sleep(0.4)
        assert proc.poll() is None, 'Manager stopped instead of continuously monitoring.'

        later_name = f'LaTe Arrival {token}.DAT'
        later_text = 'Piñata façade — second arrival'
        later_source = input_dir / later_name
        later_destination = output_dir / (later_name.lower().replace(' ', '_') + '.processed')
        later_source.write_bytes(later_text.encode('cp1252'))
        wait_for_processing(proc, later_source, later_destination, later_text)

        assert list(input_dir.iterdir()) == [], 'Input directory was not cleaned up.'
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
