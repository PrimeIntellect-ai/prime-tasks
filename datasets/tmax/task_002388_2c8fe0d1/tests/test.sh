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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import secrets
import socket
import sqlite3
import time
from datetime import datetime, timezone

import pytest
import redis
import requests

BASE_URL = "http://127.0.0.1:8080"


def _listener_pids(ip, port):
    inodes = set()
    with open('/proc/net/tcp', 'r') as f:
        next(f)
        for line in f:
            fields = line.split()
            local_hex, port_hex = fields[1].split(':')
            if fields[3] != '0A' or int(port_hex, 16) != port:
                continue
            local_ip = socket.inet_ntoa(bytes.fromhex(local_hex)[::-1])
            if local_ip == ip:
                inodes.add(fields[9])

    pids = set()
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        fd_dir = f'/proc/{name}/fd'
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f'{fd_dir}/{fd}')
                except OSError:
                    continue
                if target.startswith('socket:[') and target[8:-1] in inodes:
                    pids.add(int(name))
        except OSError:
            continue
    return pids


def _cmdline(pid):
    try:
        with open(f'/proc/{pid}/cmdline', 'rb') as f:
            return f.read().replace(b'\0', b' ').decode(errors='replace')
    except OSError:
        return ''


def _assert_listener(ip, port, command_fragment):
    pids = _listener_pids(ip, port)
    assert pids, f'No process is listening on {ip}:{port}'
    commands = [_cmdline(pid) for pid in pids]
    assert any(command_fragment in command for command in commands), \
        f'{ip}:{port} is not owned by expected {command_fragment} service: {commands}'


def _wait_for_record(record_id, timeout=15):
    deadline = time.time() + timeout
    last_status = None
    last_body = None
    while time.time() < deadline:
        try:
            response = requests.get(f'{BASE_URL}/query', params={'id': record_id}, timeout=2)
            last_status = response.status_code
            last_body = response.text
            if response.status_code == 200:
                return response.json()
        except (requests.RequestException, ValueError) as exc:
            last_body = str(exc)
        time.sleep(0.25)
    pytest.fail(f'Record {record_id!r} was not queryable; last status={last_status}, body={last_body}')


def _assert_record(actual, expected):
    for key, value in expected.items():
        assert actual.get(key) == value, f'{key}: expected {value!r}, got {actual.get(key)!r}'


def test_00_required_services_and_files():
    assert os.path.isfile('/app/worker.py'), '/app/worker.py is missing'
    assert os.path.isfile('/home/user/nginx.conf'), '/home/user/nginx.conf is missing'

    _assert_listener('127.0.0.1', 6379, 'redis-server')
    _assert_listener('127.0.0.1', 5001, 'ingestion.py')
    _assert_listener('127.0.0.1', 5002, 'query.py')
    _assert_listener('127.0.0.1', 8080, 'nginx')

    process_commands = []
    for name in os.listdir('/proc'):
        if name.isdigit():
            process_commands.append(_cmdline(int(name)))
    assert any('worker.py' in command for command in process_commands), 'The data worker is not running'

    broker = redis.Redis(host='127.0.0.1', port=6379, db=0)
    assert broker.ping() is True
    broker.delete('raw_data')


def test_end_to_end_pipeline():
    base_url = "http://127.0.0.1:8080"

    # 1. Send CSV payload
    csv_payload = {
        "format": "csv",
        "data": "id,timestamp,review_text\n1,1672531200,\"This is a great product,\nI really loved it!\"\n2,12/31/2022 15:30,\"Terrible.\""
    }
    try:
        res_csv = requests.post(f"{base_url}/ingest", json=csv_payload, timeout=5)
        assert res_csv.status_code == 200, f"Failed to post CSV payload, status code: {res_csv.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080 or ingestion service: {e}")

    # 2. Send JSON payload
    json_payload = {
        "format": "json",
        "data": "[{\"id\":\"3\",\"timestamp\":\"1672617600\",\"review_text\":\"Okay product\"}]"
    }
    try:
        res_json = requests.post(f"{base_url}/ingest", json=json_payload, timeout=5)
        assert res_json.status_code == 200, f"Failed to post JSON payload, status code: {res_json.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to Nginx on port 8080 or ingestion service: {e}")

    # 3. Wait for worker to process
    time.sleep(3)

    # 4. Query ID 1
    try:
        res_q1 = requests.get(f"{base_url}/query?id=1", timeout=5)
        assert res_q1.status_code == 200, f"Query for ID 1 failed with status code: {res_q1.status_code}"
        data_q1 = res_q1.json()
        assert data_q1.get("id") == "1", f"Expected id '1', got {data_q1.get('id')}"
        assert data_q1.get("timestamp") == "2023-01-01 00:00:00", f"Expected timestamp '2023-01-01 00:00:00', got {data_q1.get('timestamp')}"
        assert data_q1.get("review_text") == "This is a great product,\nI really loved it!", f"Expected specific review text with newline, got {data_q1.get('review_text')}"
        assert data_q1.get("word_count") == 9, f"Expected word_count 9, got {data_q1.get('word_count')}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to query ID 1: {e}")
    except ValueError:
        pytest.fail(f"Response for ID 1 was not valid JSON: {res_q1.text}")

    # 5. Query ID 2
    try:
        res_q2 = requests.get(f"{base_url}/query?id=2", timeout=5)
        assert res_q2.status_code == 200, f"Query for ID 2 failed with status code: {res_q2.status_code}"
        data_q2 = res_q2.json()
        assert data_q2.get("id") == "2", f"Expected id '2', got {data_q2.get('id')}"
        assert data_q2.get("timestamp") == "2022-12-31 15:30:00", f"Expected timestamp '2022-12-31 15:30:00', got {data_q2.get('timestamp')}"
        assert data_q2.get("review_text") == "Terrible.", f"Expected review text 'Terrible.', got {data_q2.get('review_text')}"
        assert data_q2.get("word_count") == 1, f"Expected word_count 1, got {data_q2.get('word_count')}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to query ID 2: {e}")
    except ValueError:
        pytest.fail(f"Response for ID 2 was not valid JSON: {res_q2.text}")

    # 6. Query ID 3
    try:
        res_q3 = requests.get(f"{base_url}/query?id=3", timeout=5)
        assert res_q3.status_code == 200, f"Query for ID 3 failed with status code: {res_q3.status_code}"
        data_q3 = res_q3.json()
        assert data_q3.get("id") == "3", f"Expected id '3', got {data_q3.get('id')}"
        assert data_q3.get("timestamp") == "2023-01-02 00:00:00", f"Expected timestamp '2023-01-02 00:00:00', got {data_q3.get('timestamp')}"
        assert data_q3.get("review_text") == "Okay product", f"Expected review text 'Okay product', got {data_q3.get('review_text')}"
        assert data_q3.get("word_count") == 2, f"Expected word_count 2, got {data_q3.get('word_count')}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to query ID 3: {e}")
    except ValueError:
        pytest.fail(f"Response for ID 3 was not valid JSON: {res_q3.text}")


def test_randomized_pipeline_and_redis_worker_path():
    token = secrets.token_hex(8)
    epoch = 1680000000 + secrets.randbelow(10000000)
    expected_epoch = datetime.fromtimestamp(epoch, timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
    minute = secrets.randbelow(60)

    csv_records = [
        {
            'id': f'{token}-csv-a',
            'timestamp': str(epoch),
            'review_text': f'alpha {token}, quoted \"value\"\ncontinues on another line'
        },
        {
            'id': f'{token}-csv-b',
            'timestamp': f'07/14/2021 09:{minute:02d}',
            'review_text': f'{token} second randomized review'
        }
    ]
    buf = io.StringIO(newline='')
    writer = csv.DictWriter(buf, fieldnames=['id', 'timestamp', 'review_text'], lineterminator='\n')
    writer.writeheader()
    writer.writerows(csv_records)

    response = requests.post(BASE_URL + '/ingest', json={'format': 'csv', 'data': buf.getvalue()}, timeout=5)
    assert response.status_code == 200

    json_record = {
        'id': f'{token}-json',
        'timestamp': str(epoch + 86400),
        'review_text': f'json {token} has several distinct words'
    }
    response = requests.post(
        BASE_URL + '/ingest',
        json={'format': 'json', 'data': json.dumps([json_record])},
        timeout=5
    )
    assert response.status_code == 200

    direct_record = {
        'id': f'{token}-redis',
        'timestamp': '03/05/2020 06:07',
        'review_text': f'direct redis {token} worker check'
    }
    broker = redis.Redis(host='127.0.0.1', port=6379, db=0)
    broker.lpush('raw_data', json.dumps({'format': 'json', 'data': json.dumps([direct_record])}))

    expected = {
        csv_records[0]['id']: {
            'id': csv_records[0]['id'], 'timestamp': expected_epoch,
            'review_text': csv_records[0]['review_text'],
            'word_count': len(csv_records[0]['review_text'].split())
        },
        csv_records[1]['id']: {
            'id': csv_records[1]['id'], 'timestamp': f'2021-07-14 09:{minute:02d}:00',
            'review_text': csv_records[1]['review_text'],
            'word_count': len(csv_records[1]['review_text'].split())
        },
        json_record['id']: {
            'id': json_record['id'],
            'timestamp': datetime.fromtimestamp(epoch + 86400, timezone.utc).strftime('%Y-%m-%d %H:%M:%S'),
            'review_text': json_record['review_text'],
            'word_count': len(json_record['review_text'].split())
        },
        direct_record['id']: {
            'id': direct_record['id'], 'timestamp': '2020-03-05 06:07:00',
            'review_text': direct_record['review_text'],
            'word_count': len(direct_record['review_text'].split())
        }
    }

    for record_id, wanted in expected.items():
        _assert_record(_wait_for_record(record_id), wanted)

    assert os.path.isfile('/home/user/pipeline/clean.db')
    conn = sqlite3.connect('/home/user/pipeline/clean.db')
    try:
        schema = conn.execute('PRAGMA table_info(reviews)').fetchall()
        assert [(row[1], row[2].upper()) for row in schema] == [
            ('id', 'TEXT'), ('timestamp', 'TEXT'), ('review_text', 'TEXT'), ('word_count', 'INTEGER')
        ]
        assert schema[0][5] == 1, 'reviews.id must be the primary key'
        for record_id, wanted in expected.items():
            row = conn.execute(
                'SELECT id, timestamp, review_text, word_count FROM reviews WHERE id = ?',
                (record_id,)
            ).fetchone()
            assert row == (wanted['id'], wanted['timestamp'], wanted['review_text'], wanted['word_count'])
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
