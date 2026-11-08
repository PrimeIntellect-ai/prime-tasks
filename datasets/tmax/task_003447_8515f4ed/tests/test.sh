#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import subprocess
import threading
import time
import uuid

import pytest

SCRIPT_PATH = "/home/user/sync_projects.sh"
MASTER_INDEX = "/home/user/master_index.json"
DROPZONE = "/home/user/dropzone"
LEGACY = "/home/user/legacy_projects"


def wait_for_index(expected, timeout=10):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            with open(MASTER_INDEX) as f:
                last = json.load(f)
            if isinstance(last, dict) and all(last.get(k) == v for k, v in expected.items()):
                return last
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(0.1)
    pytest.fail(f"Master index did not contain expected records {expected}; last value was {last!r}")


def stop_old_service():
    victims = []
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode(errors='ignore')
        except OSError:
            continue
        if SCRIPT_PATH in cmd or ('inotifywait' in cmd and DROPZONE in cmd):
            victims.append(int(entry))
    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def watcher_uses_close_write():
    for entry in os.listdir('/proc'):
        if not entry.isdigit():
            continue
        try:
            with open(f'/proc/{entry}/cmdline', 'rb') as f:
                cmd = f.read().replace(b'\0', b' ').decode(errors='ignore').lower()
        except OSError:
            continue
        if 'inotifywait' in cmd and 'close_write' in cmd and DROPZONE.lower() in cmd:
            return True
    return False


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_uses_atomic_mv():
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read()
    assert "mv " in content and "master_index.json" in content, "Script does not appear to use atomic 'mv' to update master_index.json."


def test_full_service_behavior():
    stop_old_service()
    os.makedirs(DROPZONE, exist_ok=True)
    for name in os.listdir(DROPZONE):
        path = os.path.join(DROPZONE, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    try:
        os.unlink(MASTER_INDEX)
    except FileNotFoundError:
        pass

    token = uuid.uuid4().hex
    nested = os.path.join(LEGACY, 'audit', token, 'deep')
    os.makedirs(nested, exist_ok=True)
    initial_json_name = f'LegacyJson_{token}'
    initial_csv_name1 = f'LegacyCsvA_{token}'
    initial_csv_name2 = f'LegacyCsvB_{token}'
    with open(os.path.join(nested, 'random.json'), 'w') as f:
        json.dump({'id': 8001, 'project_name': initial_json_name, 'status': f'json_{token}'}, f)
    with open(os.path.join(nested, 'random.csv'), 'w') as f:
        f.write('id,project_name,status\n')
        f.write(f'8002,{initial_csv_name1},csv_a_{token}\n')
        f.write(f'8003,{initial_csv_name2},csv_b_{token}\n')

    subprocess.Popen(
        [SCRIPT_PATH], cwd='/home/user', stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )

    initial_expected = {
        'Apollo': 'active',
        'Gemini': 'archived',
        initial_json_name: f'json_{token}',
        initial_csv_name1: f'csv_a_{token}',
        initial_csv_name2: f'csv_b_{token}',
    }
    data = wait_for_index(initial_expected)

    assert os.path.isfile(MASTER_INDEX), f"{MASTER_INDEX} does not exist. The script might not have run the initial scan."
    with open(MASTER_INDEX, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{MASTER_INDEX} is not valid JSON.")
    assert data.get("Apollo") == "active", "Initial scan missing or incorrect 'Apollo' project from JSON file."
    assert data.get("Gemini") == "archived", "Initial scan missing or incorrect 'Gemini' project from CSV file."
    assert isinstance(data, dict), "Master index must be a JSON object."

    deadline = time.time() + 6
    while time.time() < deadline and not watcher_uses_close_write():
        time.sleep(0.1)
    assert watcher_uses_close_write(), "No inotifywait process watching the dropzone for close_write was found."

    event_log = '/tmp/master_atomic_events.log'
    event_output = open(event_log, 'w')
    monitor = subprocess.Popen(
        ['inotifywait', '-m', '-e', 'create,modify,close_write,moved_from,moved_to',
         '--format', '%e|%f', '/home/user'],
        stdout=event_output, stderr=subprocess.DEVNULL, text=True
    )
    time.sleep(0.4)
    assert monitor.poll() is None, "Could not monitor index updates for atomic replacement."

    reader_errors = []
    reader_stop = threading.Event()

    def continuous_reader():
        while not reader_stop.is_set():
            try:
                with open(MASTER_INDEX) as f:
                    value = json.load(f)
                if not isinstance(value, dict):
                    reader_errors.append('index was not an object')
            except Exception as exc:
                reader_errors.append(repr(exc))
            time.sleep(0.005)

    reader = threading.Thread(target=continuous_reader, daemon=True)
    reader.start()

    try:
        assert os.path.isdir(DROPZONE), f"Dropzone directory {DROPZONE} missing."

        new_file_path = os.path.join(DROPZONE, "new_proj.json")
        new_data = {"id": 103, "project_name": "Orion", "status": "planning"}
        with open(new_file_path, 'w') as f:
            json.dump(new_data, f)
        data = wait_for_index({'Orion': 'planning', **initial_expected})

        assert os.path.isfile(MASTER_INDEX), f"{MASTER_INDEX} does not exist after dropping new file."
        with open(MASTER_INDEX, 'r') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"{MASTER_INDEX} is not valid JSON after update.")
        assert data.get("Orion") == "planning", "Dropzone file was not processed or master index not updated with 'Orion'."
        assert data.get("Apollo") == "active", "'Apollo' project was lost after dropzone update."
        assert data.get("Gemini") == "archived", "'Gemini' project was lost after dropzone update."

        held_name = f'HeldUntilClose_{token}'
        held_path = os.path.join(DROPZONE, f'held_{token}.json')
        held = open(held_path, 'w')
        json.dump({'id': 9001, 'project_name': held_name, 'status': f'closed_{token}'}, held)
        held.flush()
        os.fsync(held.fileno())
        time.sleep(2)
        with open(MASTER_INDEX) as f:
            before_close = json.load(f)
        assert held_name not in before_close, "A dropzone file was processed before its close_write event."
        held.close()
        wait_for_index({held_name: f'closed_{token}', 'Orion': 'planning', **initial_expected})

        drop_csv_name1 = f'DropCsvA_{token}'
        drop_csv_name2 = f'DropCsvB_{token}'
        csv_path = os.path.join(DROPZONE, f'drop_{token}.csv')
        with open(csv_path, 'w') as f:
            f.write('id,project_name,status\n')
            f.write(f'9002,{drop_csv_name1},drop_a_{token}\n')
            f.write(f'9003,{drop_csv_name2},drop_b_{token}\n')
        wait_for_index({
            drop_csv_name1: f'drop_a_{token}',
            drop_csv_name2: f'drop_b_{token}',
            held_name: f'closed_{token}',
            'Orion': 'planning',
            **initial_expected,
        })
        time.sleep(0.5)
    finally:
        reader_stop.set()
        reader.join(timeout=2)
        monitor.terminate()
        try:
            monitor.wait(timeout=2)
        except subprocess.TimeoutExpired:
            monitor.kill()
            monitor.wait(timeout=2)
        event_output.close()

    assert not reader_errors, f"Concurrent readers observed a missing, partial, or invalid index: {reader_errors[:3]}"

    events = []
    with open(event_log) as f:
        for line in f:
            event, sep, filename = line.strip().partition('|')
            if sep:
                events.append((event, filename))

    master_positions = [i for i, (_, name) in enumerate(events) if name == 'master_index.json']
    assert master_positions, "No filesystem replacement events were observed for master_index.json."
    for pos in master_positions:
        event, _ = events[pos]
        assert 'MOVED_TO' in event, f"master_index.json was updated non-atomically via {event}."
        assert pos > 0 and 'MOVED_FROM' in events[pos - 1][0], "Index was not renamed from a temporary file in /home/user."
        temp_name = events[pos - 1][1]
        assert temp_name != 'master_index.json', "Atomic replacement did not use a distinct temporary file."
        assert any('CLOSE_WRITE' in ev and name == temp_name for ev, name in events[:pos]), \
            "Temporary index was not written and closed in the same directory before mv."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
