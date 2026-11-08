#!/bin/bash
set -e
mkdir -p /logs/verifier

# Replace the random API with a deterministic one available only during verification.
pkill -f '[a]pp/services/api.py' 2>/dev/null || true
sleep 1

# Ensure Redis is available and populate it with deterministic categories.
if ! redis-cli ping >/dev/null 2>&1; then
    redis-server --daemonize yes
    sleep 1
fi
redis-cli FLUSHDB >/dev/null
python3 - <<'PY' | redis-cli --pipe >/dev/null
for uid in range(1000, 10000):
    category = {0: 'premium', 1: 'standard', 2: 'spam'}.get(uid % 4)
    if category is not None:
        print(f'SET user:{uid} {category}')
PY

cat <<'PY' > /tmp/mock_logs_api.py
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

records = []
events = ['  User CLICKED! ', 'Logged IN.', 'Error 404...', '  Purchased item!']
types = ['guest', 'registered', 'admin']
for i in range(10000):
    records.append({
        'timestamp': f'2023-10-01T{i % 24:02d}:{(i * 7) % 60:02d}:10Z',
        'user_id': str(1000 + (i % 9000)),
        'event_text': events[i % len(events)],
        'user_type': types[i % len(types)],
    })

payload = ''.join(json.dumps(r, separators=(',', ':')) + '\n' for r in records).encode()
with open('/tmp/verifier_source_logs.jsonl', 'wb') as f:
    f.write(payload)

state = {'requests': 0, 'completed': 0, 'lines': len(records)}
lock = threading.Lock()

def save_state():
    tmp = '/tmp/verifier_api_state.json.tmp'
    with open(tmp, 'w') as f:
        json.dump(state, f)
    os.replace(tmp, '/tmp/verifier_api_state.json')

save_state()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/logs':
            self.send_error(404)
            return
        with lock:
            state['requests'] += 1
            save_state()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        try:
            self.wfile.write(payload)
            self.wfile.flush()
            with lock:
                state['completed'] += 1
                save_state()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, fmt, *args):
        pass

class Server(HTTPServer):
    allow_reuse_address = True

Server(('127.0.0.1', 8080), Handler).serve_forever()
PY

python3 /tmp/mock_logs_api.py >/tmp/mock_logs_api.log 2>&1 &
MOCK_PID=$!
cleanup() {
    kill "$MOCK_PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 1 50); do
    [ -f /tmp/verifier_api_state.json ] && break
    sleep 0.1
done

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import json
import os
import re
import subprocess
import time

SCRIPT = '/home/user/pipeline.sh'
CSV_PATH = '/home/user/cleaned_dataset.csv'


def redis_category(user_id):
    value = subprocess.check_output(
        ['redis-cli', '--raw', 'GET', f'user:{user_id}'], text=True
    ).rstrip('\n')
    return value if value else 'unknown'


def cleaned_event(value):
    return re.sub(r'[^\w\s]', '', value.lower().strip())


def test_pipeline_output_and_cron():
    assert os.path.isfile(SCRIPT), f'{SCRIPT} does not exist or is not a regular file.'
    assert os.access(SCRIPT, os.X_OK), f'{SCRIPT} is not executable.'

    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)

    result = subprocess.run(
        [SCRIPT], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300
    )
    assert result.returncode == 0, (
        f'Pipeline exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout[-2000:]}\n'
        f'stderr:\n{result.stderr[-2000:]}'
    )
    assert os.path.exists(CSV_PATH), f'Output file {CSV_PATH} does not exist.'

    # Confirm that this execution fetched the complete, exactly-10,000-line stream.
    state = None
    for _ in range(20):
        with open('/tmp/verifier_api_state.json') as f:
            state = json.load(f)
        if state.get('completed') == 1:
            break
        time.sleep(0.1)
    assert state == {'requests': 1, 'completed': 1, 'lines': 10000}, (
        f'Pipeline did not fetch exactly one complete 10,000-line API stream: {state}'
    )

    with open(CSV_PATH, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['hour', 'user_id', 'event_clean', 'user_category', 'user_type'], (
            "CSV headers are incorrect. Expected "
            "['hour', 'user_id', 'event_clean', 'user_category', 'user_type'], "
            f'got {reader.fieldnames}'
        )
        rows = list(reader)

    # Preserve the original structural and formatting assertions.
    counts = {'guest': 0, 'registered': 0, 'admin': 0}
    hour_ok = 0
    clean_ok = 0
    cat_ok = 0
    for row in rows:
        user_type = row.get('user_type', '')
        counts[user_type] = counts.get(user_type, 0) + 1

        hour = row.get('hour', '')
        if hour.isdigit() and 0 <= int(hour) <= 23:
            hour_ok += 1

        event = row.get('event_clean', '')
        if event == event.lower().strip() and not re.search(r'[^\w\s]', event):
            clean_ok += 1

        category = row.get('user_category', '')
        if category in ['premium', 'standard', 'spam', 'unknown']:
            cat_ok += 1

    score = 0.0
    if counts == {'guest': 100, 'registered': 100, 'admin': 100}:
        score += 0.3
    if hour_ok == 300:
        score += 0.2
    if clean_ok == 300:
        score += 0.2
    if cat_ok == 300:
        score += 0.2

    crontab = ''
    try:
        crontab = subprocess.check_output(
            ['crontab', '-l'], stderr=subprocess.DEVNULL, text=True
        )
        if '*/5 * * * *' in crontab and SCRIPT in crontab:
            score += 0.1
    except subprocess.CalledProcessError:
        pass

    assert score >= 0.95, (
        f'Pipeline score {score:.2f} is below the 0.95 threshold. '
        f'Details: counts={counts}, hour_ok={hour_ok}/300, '
        f'clean_ok={clean_ok}/300, cat_ok={cat_ok}/300'
    )

    assert len(rows) == 300

    # Derive every permissible output row from the API records and current Redis
    # values, then enforce source membership, exact cleaning, and enrichment.
    with open('/tmp/verifier_source_logs.jsonl') as f:
        source = [json.loads(line) for line in f]
    assert len(source) == 10000

    categories = {record['user_id'] for record in source}
    categories = {uid: redis_category(uid) for uid in categories}

    expected = collections.Counter()
    for record in source:
        expected[(
            record['timestamp'][11:13],
            record['user_id'],
            cleaned_event(record['event_text']),
            categories[record['user_id']],
            record['user_type'],
        )] += 1

    actual = collections.Counter(
        (row['hour'], row['user_id'], row['event_clean'],
         row['user_category'], row['user_type'])
        for row in rows
    )
    invalid = actual - expected
    assert not invalid, (
        'CSV contains rows not correctly derived from the fetched API data and '
        f'Redis enrichment: {list(invalid.items())[:5]}'
    )

    assert re.search(
        r'(?m)^\s*\*/5\s+\*\s+\*\s+\*\s+\*\s+.*(?:^|\s)/home/user/pipeline\.sh(?:\s|$)',
        crontab,
    ), 'Crontab does not schedule /home/user/pipeline.sh every five minutes.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
