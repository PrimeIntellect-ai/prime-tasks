#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import email.utils
import json
import math
import os
import random
import shutil
import socket
import subprocess
import threading
import time
import uuid
from datetime import timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

FILTER = "/home/user/filter.py"
CLEAN_DIR = "/home/user/corpora/clean"
EVIL_DIR = "/home/user/corpora/evil"
INCOMING = "/home/user/incoming_mail"
DB_PATH = "/home/user/dashboard_db.json"


def run_filter(raw):
    return subprocess.run(
        ['/usr/bin/python3', FILTER],
        input=raw.encode('utf-8'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def leaves(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from leaves(item)
    elif isinstance(value, list):
        for item in value:
            yield from leaves(item)
    else:
        yield value


def assert_payload(data, metric, number, timestamp):
    assert isinstance(data, dict), "Filter output must be a JSON object"
    values = list(leaves(data))
    assert metric in values, f"Metric {metric!r} is missing from output"
    assert timestamp in values, f"Normalized timestamp {timestamp!r} is missing from output"
    numeric = [v for v in values if isinstance(v, (int, float)) and not isinstance(v, bool)]
    assert any(math.isfinite(float(v)) and math.isclose(float(v), number, rel_tol=1e-12, abs_tol=1e-12) for v in numeric), \
        f"Numeric value {number!r} is missing from output"


def expected_utc(date_text):
    parsed = email.utils.parsedate_to_datetime(date_text)
    assert parsed is not None and parsed.tzinfo is not None
    return parsed.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def test_filter_clean_corpus():
    """Retain the original clean-corpus assertions."""
    assert os.path.isfile(FILTER), f"Missing file: {FILTER}"
    failed_files = []
    total_files = 0
    for filename in os.listdir(CLEAN_DIR):
        filepath = os.path.join(CLEAN_DIR, filename)
        if not os.path.isfile(filepath):
            continue
        total_files += 1
        with open(filepath, 'rb') as f:
            result = subprocess.run(
                ['/usr/bin/python3', FILTER], stdin=f,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        if result.returncode != 0:
            failed_files.append(filename)
            continue
        try:
            json.loads(result.stdout.decode('utf-8').strip())
        except Exception:
            failed_files.append(filename)
    assert total_files > 0
    assert not failed_files, f"{len(failed_files)} of {total_files} clean modified/failed: {', '.join(failed_files)}"


def test_filter_evil_corpus():
    """Retain the original evil-corpus assertions."""
    assert os.path.isfile(FILTER), f"Missing file: {FILTER}"
    failed_files = []
    total_files = 0
    for filename in os.listdir(EVIL_DIR):
        filepath = os.path.join(EVIL_DIR, filename)
        if not os.path.isfile(filepath):
            continue
        total_files += 1
        with open(filepath, 'rb') as f:
            result = subprocess.run(
                ['/usr/bin/python3', FILTER], stdin=f,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        if result.returncode == 0:
            failed_files.append(filename)
    assert total_files > 0
    assert not failed_files, f"{len(failed_files)} of {total_files} evil bypassed: {', '.join(failed_files)}"


def test_filter_semantics_and_unseen_inputs():
    token = uuid.uuid4().hex[:10]
    valid = [
        (f"metric_{token}", "-12.75", -12.75, "Fri, 05 Apr 2024 23:17:09 -0330"),
        (f"rate_{token}", "1.25e3", 1250.0, "Tue, 06 Feb 2024 04:05:06 EST"),
        (f"disk_{token}", "0.00042", 0.00042, "01 Jul 2025 00:00:01 +1245"),
    ]
    for metric, text_value, number, date_text in valid:
        raw = (
            f"From: monitor@legacy.example\r\n"
            f"Subject: [ALERT] {metric}\r\n"
            f"Date: {date_text}\r\n"
            f"Message-ID: <{uuid.uuid4().hex}@legacy.example>\r\n"
            f"\r\nDiagnostic text\r\nValue: {text_value}\r\nEnd\r\n"
        )
        result = run_filter(raw)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        data = json.loads(result.stdout.decode('utf-8'))
        assert_payload(data, metric, number, expected_utc(date_text))

    bad_messages = [
        "Subject: status only\nDate: Thu, 21 Dec 2023 15:00:00 +0200\n\nValue: 1.0\n",
        "Subject: [ALERT] cpu\nDate: definitely-not-a-date\n\nValue: 1.0\n",
        "Subject: [ALERT] cpu\n\nValue: 1.0\n",
        "Date: Thu, 21 Dec 2023 15:00:00 +0200\n\nValue: 1.0\n",
        "Subject: [ALERT] cpu\nDate: Thu, 21 Dec 2023 15:00:00 +0200\n\nValue: 1.0 extra\n",
        "Subject: [ALERT] cpu\nDate: Thu, 21 Dec 2023 15:00:00 +0200\n\n<div>Value: 1.0</div>\n",
        "Subject: [ALERT] <script>alert(1)</script>\nDate: Thu, 21 Dec 2023 15:00:00 +0200\n\nValue: 1.0\n",
        "Subject: [ALERT] cpu\nDate: Thu, 21 Dec 2023 15:00:00 +0200\n\nValue: not-a-number\n",
    ]
    for raw in bad_messages:
        result = run_filter(raw)
        assert result.returncode == 1, f"Invalid mail returned {result.returncode}: {raw!r}"
        assert result.stdout == b'', "Invalid mail must print nothing"


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


def stop_original_services():
    subprocess.run(['pkill', '-f', '^python3 /app/legacy_emitter.py'], check=False)
    subprocess.run(['pkill', '-f', '^python3 /app/dashboard_api.py'], check=False)
    time.sleep(0.5)


def bind_http(handler):
    last = None
    for _ in range(20):
        try:
            return ReusableHTTPServer(('127.0.0.1', 10080), handler)
        except OSError as exc:
            last = exc
            time.sleep(0.1)
    raise last


def test_e2e_flow():
    exp_path = "/home/user/trigger_alert.exp"
    sh_path = "/home/user/process_mail.sh"
    assert os.path.isfile(exp_path), f"Missing file: {exp_path}"
    assert os.path.isfile(sh_path), f"Missing file: {sh_path}"
    assert os.path.isfile(FILTER), f"Missing file: {FILTER}"

    stop_original_services()
    os.makedirs(INCOMING, exist_ok=True)
    for name in os.listdir(INCOMING):
        path = os.path.join(INCOMING, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    if os.path.exists(DB_PATH):
        os.unlink(DB_PATH)

    requests_seen = []
    request_lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            body = self.rfile.read(length)
            try:
                payload = json.loads(body.decode('utf-8'))
            except Exception:
                payload = None
            with request_lock:
                requests_seen.append({
                    'path': self.path,
                    'content_type': self.headers.get('Content-Type', ''),
                    'payload': payload,
                })
                with open(DB_PATH, 'w') as f:
                    json.dump([r['payload'] for r in requests_seen], f)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'OK')

        def log_message(self, fmt, *args):
            pass

    httpd = bind_http(Handler)
    http_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    http_thread.start()

    transcript = []
    emitter_errors = []
    emitter_ready = threading.Event()
    cpu_date = "Wed, 10 Jan 2024 09:08:07 +0100"

    def emitter():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(('127.0.0.1', 10023))
                server.listen(1)
                emitter_ready.set()
                server.settimeout(15)
                conn, _ = server.accept()
                with conn:
                    conn.settimeout(10)
                    stream = conn.makefile('rwb', buffering=0)
                    for prompt in [b'Username: ', b'Password: ', b'Locale: ', b'Timezone: ']:
                        stream.write(prompt)
                        line = stream.readline().decode('utf-8', errors='replace').rstrip('\r\n')
                        transcript.append(line)
                    while True:
                        stream.write(b'> ')
                        line = stream.readline().decode('utf-8', errors='replace').rstrip('\r\n')
                        transcript.append(line)
                        if line == 'EMIT cpu_load 0.85':
                            with open(os.path.join(INCOMING, '10-live-alert.eml'), 'w') as f:
                                f.write(f"Subject: [ALERT] cpu_load\nDate: {cpu_date}\n\nValue: 0.85\n")
                        if line == 'QUIT' or line == '':
                            break
        except Exception as exc:
            emitter_errors.append(repr(exc))
            emitter_ready.set()

    emitter_thread = threading.Thread(target=emitter, daemon=True)
    emitter_thread.start()
    assert emitter_ready.wait(5), "Mock legacy emitter did not start"

    # Original verifier action: run the submitted Expect script.
    exp_result = subprocess.run(['/usr/bin/expect', exp_path], capture_output=True, timeout=15)
    assert exp_result.returncode == 0, f"trigger_alert.exp failed: {exp_result.stderr.decode(errors='replace')}"
    emitter_thread.join(5)
    assert not emitter_errors, f"Legacy interaction failed: {emitter_errors}"
    assert transcript == [
        'admin', 'observability', 'en_US.UTF-8', 'Europe/Paris',
        'EMIT cpu_load 0.85', 'QUIT'
    ], f"Incorrect legacy interaction: {transcript!r}"

    random_metric = 'probe_' + uuid.uuid4().hex[:12]
    random_value = round(random.SystemRandom().uniform(10.0, 90.0), 4)
    random_date = "Sat, 17 Aug 2024 02:03:04 -0430"
    random_path = os.path.join(INCOMING, '20-' + uuid.uuid4().hex + '.eml')
    with open(random_path, 'w') as f:
        f.write(
            f"From: verifier@legacy\nSubject: [ALERT] {random_metric}\n"
            f"Date: {random_date}\n\nValue: {random_value}\n"
        )
    invalid_path = os.path.join(INCOMING, '30-' + uuid.uuid4().hex + '.eml')
    with open(invalid_path, 'w') as f:
        f.write("Subject: [ALERT] reject_me\nDate: broken\n\nValue: nope\n")

    # Wrap the submitted filter temporarily so we can verify process_mail.sh actually invokes it.
    original_filter = '/tmp/filter-original-' + uuid.uuid4().hex + '.py'
    invocation_log = '/tmp/filter-invocations-' + uuid.uuid4().hex
    shutil.move(FILTER, original_filter)
    with open(FILTER, 'w') as f:
        f.write(
            "#!/usr/bin/python3\n"
            "import os\n"
            f"with open({invocation_log!r}, 'a') as log: log.write('called\\n')\n"
            f"os.execv('/usr/bin/python3', ['/usr/bin/python3', {original_filter!r}])\n"
        )
    os.chmod(FILTER, 0o755)
    try:
        # Original verifier action: run the submitted processing script.
        sh_result = subprocess.run(['/bin/bash', sh_path], capture_output=True, timeout=20)
    finally:
        os.unlink(FILTER)
        shutil.move(original_filter, FILTER)

    assert sh_result.returncode == 0, f"process_mail.sh failed: {sh_result.stderr.decode(errors='replace')}"
    calls = 0
    if os.path.exists(invocation_log):
        with open(invocation_log) as f:
            calls = sum(1 for line in f if line.strip() == 'called')
        os.unlink(invocation_log)
    assert calls >= 3, f"process_mail.sh did not pass every incoming file through filter.py (calls={calls})"
    assert not [n for n in os.listdir(INCOMING) if os.path.isfile(os.path.join(INCOMING, n))], \
        "Processed valid and invalid mail files must all be deleted"

    httpd.shutdown()
    httpd.server_close()
    http_thread.join(3)

    with request_lock:
        captured = list(requests_seen)
    assert len(captured) == 2, f"Expected exactly two valid dashboard POSTs, got {len(captured)}"
    for request in captured:
        assert request['path'] == '/ingest', f"Wrong dashboard path: {request['path']}"
        assert request['content_type'].lower().startswith('application/json'), \
            f"Wrong Content-Type: {request['content_type']}"
        assert isinstance(request['payload'], dict), "Dashboard payload was not a JSON object"

    payloads = [r['payload'] for r in captured]
    assert any(
        (assertable_payload(p, 'cpu_load', 0.85, expected_utc(cpu_date))) for p in payloads
    ), "Live cpu_load payload was not posted correctly"
    assert any(
        (assertable_payload(p, random_metric, random_value, expected_utc(random_date))) for p in payloads
    ), "Unseen generated payload was not posted correctly"

    # Retain the original final-state assertions.
    assert os.path.isfile(DB_PATH), f"Missing file: {DB_PATH} (dashboard did not receive data)"
    with open(DB_PATH, 'r') as f:
        content = f.read()
    assert "cpu_load" in content, "Metric 'cpu_load' not found in dashboard_db.json"
    assert "0.85" in content, "Value 0.85 not found in dashboard_db.json"


def assertable_payload(payload, metric, number, timestamp):
    try:
        assert_payload(payload, metric, number, timestamp)
        return True
    except AssertionError:
        return False
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
