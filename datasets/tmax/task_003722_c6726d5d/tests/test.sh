#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop fixture writers and any stale watcher process so the behavioral test has
# exclusive control over the live log.
pkill -f '[w]riter.sh' 2>/dev/null || true
pkill -f '[w]atcher.py' 2>/dev/null || true
sleep 0.3

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import time
import uuid


def test_tmp_files_cleanup():
    small_tmp = '/home/user/project/small.tmp'
    large1_tmp = '/home/user/project/large1.tmp'
    large2_tmp = '/home/user/project/sub/large2.tmp'

    assert os.path.isfile(small_tmp), f"FAIL: {small_tmp} should not have been deleted (it is <= 10KB)."
    assert not os.path.exists(large1_tmp), f"FAIL: {large1_tmp} was not deleted (it is > 10KB)."
    assert not os.path.exists(large2_tmp), f"FAIL: {large2_tmp} was not deleted (it is > 10KB)."


def test_config_updated():
    config_path = '/home/user/project/config.ini'
    assert os.path.isfile(config_path), f"FAIL: {config_path} is missing."

    with open(config_path, 'r') as f:
        content = f.read()

    assert 'LOG_LEVEL=INFO' in content, "FAIL: config.ini does not contain LOG_LEVEL=INFO."
    assert 'LOG_LEVEL=DEBUG' not in content, "FAIL: config.ini still contains LOG_LEVEL=DEBUG."


def test_errors_found_log():
    log_path = '/home/user/project/errors_found.log'
    assert os.path.isfile(log_path), f"FAIL: {log_path} was not created."

    with open(log_path, 'r') as f:
        content = f.read()

    error_count = len(re.findall(r'^\[ERROR\]', content, re.MULTILINE))
    info_count = len(re.findall(r'^\[INFO\]', content, re.MULTILINE))

    assert error_count == 3, f"FAIL: Expected exactly 3 [ERROR] records, found {error_count}."
    assert info_count == 0, f"FAIL: Expected 0 [INFO] records, found {info_count}."
    assert "Traceback" in content, "FAIL: Multi-line traceback content is missing from the parsed errors."


def test_watcher_tails_and_parses_live_records():
    watcher_path = '/home/user/watcher.py'
    live_path = '/home/user/project/live.log'
    output_path = '/home/user/project/errors_found.log'

    assert os.path.isfile(watcher_path), f"FAIL: {watcher_path} does not exist or is not a file."

    # Use unpredictable records written only after watcher.py starts. This
    # verifies that the output is obtained by watching and parsing live.log.
    nonce = uuid.uuid4().hex
    error_blocks = []
    for number in range(1, 5):
        error_blocks.append([
            f'[ERROR] {nonce} error-{number}',
            f'    Traceback {nonce} trace-{number}',
            f'      File "{nonce}_{number}.py", line {40 + number}, in <module>',
            f'    ValueError: {nonce} value-{number}',
        ])

    emitted_blocks = [
        [f'[INFO] {nonce} prelude'],
        error_blocks[0],
        error_blocks[1],
        error_blocks[2],
        [f'[INFO] {nonce} completes-third-error'],
        error_blocks[3],
        [f'[INFO] {nonce} completes-fourth-error'],
    ]

    with open(live_path, 'w'):
        pass
    if os.path.exists(output_path):
        os.remove(output_path)

    proc = subprocess.Popen(
        ['python3', watcher_path],
        cwd='/home/user/project',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        time.sleep(0.7)
        assert proc.poll() is None, "FAIL: watcher.py exited before any live records were written."

        with open(live_path, 'a', buffering=1) as live:
            for block in emitted_blocks:
                live.write('\n'.join(block) + '\n')
                live.flush()
                os.fsync(live.fileno())
                time.sleep(0.25)

        try:
            proc.wait(timeout=12)
        except subprocess.TimeoutExpired:
            raise AssertionError("FAIL: watcher.py did not exit after three complete error records.")

        stdout, stderr = proc.communicate()
        assert proc.returncode == 0, (
            f"FAIL: watcher.py exited with status {proc.returncode}. "
            f"stdout={stdout!r}, stderr={stderr!r}"
        )
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()

    assert os.path.isfile(output_path), "FAIL: watcher.py did not generate errors_found.log."
    with open(output_path, 'r') as output:
        content = output.read()

    records = []
    current = None
    for line in content.splitlines():
        if line.startswith('['):
            if current is not None:
                records.append(current)
            current = [line]
        elif current is not None:
            current.append(line)
    if current is not None:
        records.append(current)

    normalized_records = [
        [line.strip() for line in record if line.strip()]
        for record in records
    ]
    normalized_expected = [
        [line.strip() for line in record]
        for record in error_blocks[:3]
    ]

    assert normalized_records == normalized_expected, (
        "FAIL: errors_found.log must contain exactly the first three complete "
        "live [ERROR] records, including all continuation lines and no INFO records."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
