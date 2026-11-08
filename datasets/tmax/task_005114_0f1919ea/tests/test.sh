#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import signal
import string
import subprocess
import time
from pathlib import Path

import pytest
import requests

BASE = Path('/home/user/etl_project')
RAW = BASE / 'data/raw'
REFERENCE = BASE / 'data/reference.csv'
LOG = BASE / 'logs/etl.log'
NORMALIZER = BASE / 'bin/legacy_norm'
REAL_NORMALIZER = BASE / 'bin/legacy_norm.__verifier_real'
MARKER = Path('/tmp/legacy_norm_invoked')


def get_response(category):
    url = 'http://127.0.0.1:9000/api/stats'
    try:
        return requests.get(url, params={'category': category}, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f'Failed to connect to the HTTP server: {exc}')


def assert_stats(category, expected):
    response = get_response(category)
    assert response.status_code == 200, (
        f'Expected status code 200 for category={category}, got {response.status_code}'
    )
    try:
        data = response.json()
    except (ValueError, json.JSONDecodeError):
        pytest.fail(f'Response is not valid JSON: {response.text}')
    assert data == {'category': category, 'total_count': expected}, (
        f'Unexpected response for {category}: {data}'
    )
    assert type(data['total_count']) is int


def assert_missing(category):
    response = get_response(category)
    assert response.status_code == 404, (
        f'Expected status code 404 for nonexistent category, got {response.status_code}'
    )


def read_logs():
    assert LOG.is_file(), f'Log file missing: {LOG}'
    lines = LOG.read_text().splitlines()
    assert len(lines) >= 3, f'Expected at least 3 log lines in {LOG}, got {len(lines)}'
    parsed = []
    for i, line in enumerate(lines):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f'Line {i + 1} in {LOG} is not valid JSON: {line}')
        for key in ('step', 'status', 'records'):
            assert key in entry, f"Log entry missing '{key}': {entry}"
        assert entry['status'] == 'completed', (
            f"Expected status 'completed', got {entry['status']}"
        )
        parsed.append(entry)
    assert len(parsed) >= 3
    return parsed


def listener_pid():
    inodes = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != '0A':
                continue
            local = fields[1]
            if local.rsplit(':', 1)[-1].upper() == '2328':
                inodes.add(fields[9])
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / 'fd'
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    return int(proc.name)
        except OSError:
            continue
    return None


def wait_for_server(timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if listener_pid() is not None:
            try:
                requests.get('http://127.0.0.1:9000/api/stats?category=__ready__', timeout=0.5)
                return
            except requests.exceptions.RequestException:
                pass
        time.sleep(0.15)
    pytest.fail('Relaunched Python ETL server did not listen on 127.0.0.1:9000')


def snapshot_process(pid):
    proc = Path('/proc') / str(pid)
    argv = [part.decode(errors='surrogateescape') for part in (proc / 'cmdline').read_bytes().split(b'\0') if part]
    assert argv, 'The listening server has no executable command line'
    exe = os.path.basename(os.readlink(proc / 'exe')).lower()
    assert exe.startswith('python'), f'The HTTP server must be implemented in Python, not {exe}'
    cwd = os.readlink(proc / 'cwd')
    env = {}
    for item in (proc / 'environ').read_bytes().split(b'\0'):
        if b'=' in item:
            key, value = item.split(b'=', 1)
            env[key.decode(errors='surrogateescape')] = value.decode(errors='surrogateescape')
    return argv, cwd, env


def stop_process(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 4
    while time.time() < deadline:
        if not Path(f'/proc/{pid}').exists():
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def test_complete_etl_and_server():
    # Preserve all original fixed assertions first.
    assert_stats('fruit', 5)
    assert_stats('animal', 3)
    assert_missing('nonexistent_category_123')
    read_logs()

    pid = listener_pid()
    assert pid is not None, 'No process is listening on port 9000'
    argv, cwd, env = snapshot_process(pid)

    raw_backup = {p.name: p.read_bytes() for p in RAW.glob('*.txt')}
    reference_backup = REFERENCE.read_bytes()
    child = None
    normalizer_wrapped = False

    try:
        stop_process(pid)

        nonce = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
        words = [f'alpha{nonce}', f'beta{nonce}', f'gamma{nonce}', f'delta{nonce}']
        cat_a = f'group_a_{nonce}'
        cat_b = f'group_b_{nonce}'

        for path in RAW.glob('*.txt'):
            path.unlink()
        (RAW / 'dynamic_one.txt').write_text(
            f'{words[0]} {words[0]} {words[1]} {words[2]}! {words[3]}\n'
        )
        (RAW / 'dynamic_two.txt').write_text(
            f'{words[0]}, {words[1]} {words[2]} {words[2]} {words[2]} {words[3]}.\n'
        )

        normalized = subprocess.run(
            [str(NORMALIZER)],
            input=(' '.join(words)).encode(),
            stdout=subprocess.PIPE,
            check=True,
        ).stdout.decode().split()
        assert len(normalized) == 4
        REFERENCE.write_text(
            'normalized_word,category\n'
            f'{normalized[0]},{cat_a}\n'
            f'{normalized[1]},{cat_b}\n'
            f'{normalized[2]},{cat_a}\n'
        )

        if REAL_NORMALIZER.exists():
            REAL_NORMALIZER.unlink()
        NORMALIZER.rename(REAL_NORMALIZER)
        MARKER.write_text('')
        os.chmod(MARKER, 0o666)
        NORMALIZER.write_text(
            '#!/bin/sh\n'
            f"echo invoked >> '{MARKER}'\n"
            f"exec '{REAL_NORMALIZER}' \"$@\"\n"
        )
        os.chmod(NORMALIZER, 0o755)
        normalizer_wrapped = True

        LOG.parent.mkdir(parents=True, exist_ok=True)
        LOG.write_text('')
        child = subprocess.Popen(
            argv,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        wait_for_server()

        assert MARKER.read_text().strip(), (
            'The relaunched ETL did not invoke /home/user/etl_project/bin/legacy_norm'
        )
        assert_stats(cat_a, 7)
        assert_stats(cat_b, 2)
        assert_stats('UNKNOWN', 2)
        assert_missing(f'missing_{nonce}')

        logs = read_logs()
        by_step = {}
        for entry in logs:
            step = entry['step']
            assert isinstance(step, str)
            assert type(entry['records']) is int and entry['records'] >= 0
            by_step.setdefault(step.strip().lower(), []).append(entry['records'])

        for required in ('extract', 'aggregate', 'merge'):
            assert required in by_step, f'Missing completed {required} log event'

        # Accept the conventional file/token interpretation for extraction and
        # total/distinct/category interpretations where record semantics vary.
        assert any(v in {2, 11} for v in by_step['extract']), by_step['extract']
        assert any(v in {4, 11} for v in by_step['aggregate']), by_step['aggregate']
        assert any(v in {3, 4, 11} for v in by_step['merge']), by_step['merge']
    finally:
        if child is not None and child.poll() is None:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if normalizer_wrapped:
            try:
                NORMALIZER.unlink()
            except FileNotFoundError:
                pass
            if REAL_NORMALIZER.exists():
                REAL_NORMALIZER.rename(NORMALIZER)
        for path in RAW.glob('*.txt'):
            path.unlink()
        for name, content in raw_backup.items():
            (RAW / name).write_bytes(content)
        REFERENCE.write_bytes(reference_backup)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
