#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the verifier controls the validation endpoint used during its behavioral run.
pkill -f '/app/validator.py' >/dev/null 2>&1 || true
fuser -k 8080/tcp >/dev/null 2>&1 || true

# Ensure Redis is available; the behavioral test will replace its dataset.
redis-cli -h 127.0.0.1 -p 6379 ping >/dev/null 2>&1 || redis-server --daemonize yes

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import string
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import redis


def get_ids(filepath):
    ids = set()
    try:
        with open(filepath, 'r') as f:
            for line in f:
                if line.strip():
                    data = json.loads(line)
                    assert 'id' in data, "Missing 'id' in JSON"
                    assert 'tokens' in data, "Missing 'tokens' in JSON"
                    assert isinstance(data['tokens'], list), "'tokens' must be a list"
                    ids.add(data['id'])
    except AssertionError as e:
        pytest.fail(f"Schema validation failed: {e}")
    except Exception as e:
        pytest.fail(f"Failed to read or parse {filepath}: {e}")
    return ids


def test_cleaned_dataset_f1_score():
    output_file = '/home/user/cleaned_dataset.jsonl'
    ref_file = '/app/reference_ids.json'

    assert os.path.isfile(output_file), f"Output file {output_file} is missing. The pipeline may not have produced any output or saved it to the wrong location."
    assert os.path.isfile(ref_file), f"Reference file {ref_file} is missing."

    with open(ref_file, 'r') as f:
        ground_truth_ids = set(json.load(f))

    agent_ids = get_ids(output_file)
    assert len(agent_ids) > 0, "No records found in output file. The pipeline may have dropped all records."

    true_positives = len(agent_ids.intersection(ground_truth_ids))
    false_positives = len(agent_ids - ground_truth_ids)
    false_negatives = len(ground_truth_ids - agent_ids)
    precision = true_positives / (true_positives + false_positives) if (true_positives + false_positives) > 0 else 0
    recall = true_positives / (true_positives + false_negatives) if (true_positives + false_negatives) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0

    assert f1 >= 0.95, f"F1 Score {f1:.4f} is less than the required threshold of 0.95. Precision: {precision:.4f}, Recall: {recall:.4f}"


def tokenize(text):
    table = str.maketrans('', '', string.punctuation)
    return [part.lower().translate(table) for part in text.split()]


def derive_expected(records):
    accepted = []
    output = []
    for item in records:
        tokens = tokenize(item['text'])
        token_set = set(tokens)
        duplicate = False
        for previous in accepted:
            union = token_set | previous
            similarity = len(token_set & previous) / len(union) if union else 1.0
            if similarity >= 0.75:
                duplicate = True
                break
        if not duplicate:
            accepted.append(token_set)
            output.append({'id': item['id'], 'tokens': tokens})
    return output


def test_compiled_pipeline_on_fresh_data():
    source = '/home/user/cleaner.cpp'
    binary = '/home/user/cleaner_verifier_bin'
    output_file = '/home/user/cleaned_dataset.jsonl'
    assert os.path.isfile(source), f"Required source file {source} is missing"

    compile_base = ['g++', '-std=c++17', '-O3', source, '-lhiredis', '-lpthread', '-o', binary]
    first = subprocess.run(compile_base, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if first.returncode != 0:
        second_cmd = ['g++', '-std=c++17', '-O3', source, '-lhiredis', '-lcpp-httplib', '-lpthread', '-o', binary]
        second = subprocess.run(second_cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert second.returncode == 0, f"cleaner.cpp did not compile:\n{first.stderr}\n{second.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Compilation did not produce an executable"

    nonce = ''.join(random.SystemRandom().choice(string.ascii_lowercase) for _ in range(12))
    base_id = random.SystemRandom().randint(100000, 900000)
    a, b, c = f'alpha{nonce}', f'beta{nonce}', f'gamma{nonce}'
    d, e, z = f'delta{nonce}', f'epsilon{nonce}', f'zeta{nonce}'
    records = [
        {'id': base_id,     'text': f'  {a.upper()}, {b.title()}! {c}...  '},
        {'id': base_id + 1, 'text': f'{c.upper()}? {a}; {b}.'},
        {'id': base_id + 2, 'text': f'{d},\t{e.upper()}!'},
        {'id': base_id + 3, 'text': f'{a} {b} {c} extra{nonce}'},
        {'id': base_id + 4, 'text': f'{d} {e} {z}.'},
    ]
    expected = derive_expected(records)
    expected_by_id = {item['id']: item for item in expected}
    requests_seen = []

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get('Content-Length', '0'))
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw.decode('utf-8'))
            except Exception:
                payload = None
            requests_seen.append({'path': self.path, 'content_type': self.headers.get('Content-Type'), 'payload': payload})
            valid = (
                self.path == '/validate'
                and self.headers.get('Content-Type') == 'application/json'
                and isinstance(payload, dict)
                and set(payload) == {'id', 'tokens'}
                and payload.get('id') in expected_by_id
                and payload == expected_by_id.get(payload.get('id'))
            )
            self.send_response(200 if valid else 400)
            self.end_headers()
            self.wfile.write(b'OK' if valid else b'Bad Data')

        def log_message(self, format, *args):
            pass

    class Server(ThreadingHTTPServer):
        allow_reuse_address = True

    r = redis.Redis(host='127.0.0.1', port=6379, db=0)
    r.flushdb()
    for item in records:
        r.rpush('raw_dataset', json.dumps(item))
    if os.path.exists(output_file):
        os.remove(output_file)

    server = Server(('127.0.0.1', 8080), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        run = subprocess.run([binary], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)

    assert run.returncode == 0, f"Compiled cleaner exited with {run.returncode}:\n{run.stderr}"
    assert r.llen('raw_dataset') == 0, "The cleaner did not pop all items from raw_dataset"
    assert os.path.isfile(output_file), "The executed cleaner did not create cleaned_dataset.jsonl"

    actual = []
    with open(output_file, 'r') as f:
        for line_number, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                item = json.loads(line)
            except Exception as exc:
                pytest.fail(f"Invalid JSON on output line {line_number}: {exc}")
            assert isinstance(item, dict), "Each output line must be a JSON object"
            assert set(item) == {'id', 'tokens'}, "Output records must contain exactly id and tokens"
            assert isinstance(item['id'], int) and not isinstance(item['id'], bool), "id must be an integer"
            assert isinstance(item['tokens'], list), "tokens must be a list"
            assert all(isinstance(token, str) for token in item['tokens']), "Every token must be a string"
            actual.append(item)

    assert actual == expected, f"Incorrect tokenization, ordering, schema, or deduplication. Expected {expected}, got {actual}"
    assert len(requests_seen) == len(expected), "Every accepted record, and only accepted records, must be sent for validation"
    assert [entry['payload'] for entry in requests_seen] == expected, "Validation requests contained incorrect or out-of-order payloads"
    assert all(entry['path'] == '/validate' for entry in requests_seen), "Validation requests must use /validate"
    assert all(entry['content_type'] == 'application/json' for entry in requests_seen), "Validation requests must use Content-Type: application/json"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
