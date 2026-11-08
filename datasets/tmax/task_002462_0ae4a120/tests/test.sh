#!/bin/bash
mkdir -p /logs/verifier

BACKUP=/tmp/bayes_score.verifier_backup
CLI=/app/vendor/bayes_classifier/bin/bayes_score
prep_ok=1

if [ -f "$CLI" ]; then
    cp -p "$CLI" "$BACKUP" || prep_ok=0
else
    prep_ok=0
fi

python3 - <<'PY' || prep_ok=0
import json
import secrets
from pathlib import Path

secret = secrets.token_hex(32)
Path('/tmp/verifier_secret.json').write_text(json.dumps({'secret': secret}))
wrapper = f'''#!/usr/bin/env python3
import hashlib
import hmac
import json
import sys

SECRET = {secret!r}
LOG = "/tmp/bayes_invocations.jsonl"

def main():
    try:
        pos = sys.argv.index("--input")
        data = json.loads(sys.argv[pos + 1])
    except Exception as exc:
        print(json.dumps({{"error": str(exc)}}))
        return 2

    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps({{"argv": sys.argv[1:], "data": data}}, sort_keys=True) + "\\n")

    canonical = json.dumps(data, sort_keys=True, separators=(",", ":")).encode()
    digest = hmac.new(SECRET.encode(), canonical, hashlib.sha256).hexdigest()
    score = (int(digest[:13], 16) + 1) / (16 ** 13 + 2)
    print(json.dumps({{"score": score}}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
'''
Path('/app/vendor/bayes_classifier/bin/bayes_score').write_text(wrapper)
PY
chmod +x "$CLI" 2>/dev/null || prep_ok=0
rm -f /tmp/bayes_invocations.jsonl

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import hmac
import json
import os
import re
import subprocess
from datetime import date

import pytest
import requests

BASE = "/app/vendor/bayes_classifier"
URL = "http://127.0.0.1:8080/score"
GOOD_HEADERS = {"Authorization": "Bearer secret-research-token"}
INVOCATIONS = "/tmp/bayes_invocations.jsonl"


def expected_dynamic_score(payload):
    with open('/tmp/verifier_secret.json', encoding='utf-8') as f:
        secret = json.load(f)['secret']
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    digest = hmac.new(secret.encode(), canonical, hashlib.sha256).hexdigest()
    return (int(digest[:13], 16) + 1) / (16 ** 13 + 2)


def test_vendored_package_was_fixed():
    makefile = os.path.join(BASE, "Makefile")
    extractor = os.path.join(BASE, "bin", "extract_features.sh")
    assert os.path.isfile(makefile), "Vendored Makefile is missing"
    assert os.path.isfile(extractor), "Feature extraction script is missing"
    assert os.access(extractor, os.X_OK), "Feature extraction script is not executable"

    with open(makefile, encoding="utf-8") as f:
        make_text = f.read()
    with open(extractor, encoding="utf-8") as f:
        extract_text = f.read()

    assert "/usr/bin/pyton3" not in make_text, "Makefile still contains the broken Python path"
    assert "python3" in make_text, "Makefile does not select Python 3"
    assert "/wrong/path/to/inference.py" not in extract_text, "Extractor still uses the broken inference path"
    assert extract_text.strip() != '#!/bin/bash\n# Feature extraction script\n/wrong/path/to/inference.py "$@"', "Extractor was not repaired"

    syntax = subprocess.run(["bash", "-n", extractor], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Extractor has invalid Bash syntax: {syntax.stderr}"
    built = subprocess.run(["make", "-C", BASE, "install"], capture_output=True, text=True, timeout=10)
    assert built.returncode == 0, f"Vendored package does not build/install: {built.stdout}\n{built.stderr}"

    runtime_sources = []
    for root, _, files in os.walk(BASE):
        for name in files:
            if name.endswith((".sh", ".py")):
                with open(os.path.join(root, name), encoding="utf-8", errors="ignore") as f:
                    runtime_sources.extend(line for line in f if not line.lstrip().startswith("#"))
    runtime_text = "\n".join(runtime_sources)
    prior_env_access = re.search(
        r"os\.(?:environ|getenv)|getenv\s*\(|\$\{?[A-Za-z_][A-Za-z0-9_]*PRIOR[A-Za-z0-9_]*",
        runtime_text,
        re.IGNORECASE,
    )
    assert prior_env_access, "Vendored package does not read prior probability configuration from the environment"


def test_engineered_datasets_created():
    path = "/home/user/engineered_datasets.csv"
    assert os.path.isfile(path), f"Missing engineered dataset file: {path}"

    with open(path, 'r', encoding='utf-8', newline='') as f:
        header = f.readline().strip()
    assert "time_since_creation" in header, "Engineered dataset missing 'time_since_creation' feature"
    assert "size_category" in header, "Engineered dataset missing 'size_category' feature"

    with open('/home/user/raw_datasets.csv', encoding='utf-8', newline='') as f:
        raw_rows = list(csv.DictReader(f))
    with open(path, encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames is not None
        assert 'time_since_creation' in reader.fieldnames
        assert 'size_category' in reader.fieldnames
        engineered = list(reader)

    assert len(engineered) == len(raw_rows), "Engineered CSV must contain one row per raw dataset"
    by_id = {row['dataset_id']: row for row in engineered}
    assert len(by_id) == len(engineered), "Engineered CSV contains duplicate dataset IDs"

    fixed_date = date(2023, 1, 1)
    for raw in raw_rows:
        assert raw['dataset_id'] in by_id, f"Dataset {raw['dataset_id']} is missing"
        actual = by_id[raw['dataset_id']]
        assert actual['creation_date'] == raw['creation_date']
        assert int(actual['file_size_bytes']) == int(raw['file_size_bytes'])

        expected_days = (fixed_date - date.fromisoformat(raw['creation_date'])).days
        assert float(actual['time_since_creation']) == expected_days, (
            f"Wrong time_since_creation for dataset {raw['dataset_id']}"
        )

        size = int(raw['file_size_bytes'])
        expected_category = 'small' if size < 1_000_000 else ('medium' if size < 100_000_000 else 'large')
        assert actual['size_category'] == expected_category, (
            f"Wrong size_category for dataset {raw['dataset_id']}"
        )


def test_server_log_exists():
    path = "/home/user/server.log"
    assert os.path.isfile(path), f"Missing server log file: {path}"


def test_api_server_unauthorized():
    open(INVOCATIONS, 'w').close()
    payload = {"time_since_creation": 150, "size_category": "medium"}
    try:
        response = requests.post(URL, json=payload, timeout=2)
        assert response.status_code in (401, 403), f"Expected 401 or 403 for unauthorized request, got {response.status_code}"
        wrong = requests.post(URL, json=payload, headers={"Authorization": "Bearer wrong-token"}, timeout=2)
        assert wrong.status_code in (401, 403), f"Expected 401 or 403 for an invalid token, got {wrong.status_code}"
    except requests.exceptions.ConnectionError:
        pytest.fail("API server is not running or not reachable on 127.0.0.1:8080")
    assert os.path.getsize(INVOCATIONS) == 0, "Unauthorized requests must not invoke the classifier"


def test_api_server_authorized():
    payloads = [
        {"time_since_creation": 37, "size_category": "small"},
        {"time_since_creation": -219, "size_category": "medium"},
        {"time_since_creation": 804, "size_category": "large"},
    ]

    for payload in payloads:
        try:
            response = requests.post(URL, json=payload, headers=GOOD_HEADERS, timeout=5)
        except requests.exceptions.ConnectionError:
            pytest.fail("API server is not running or not reachable on 127.0.0.1:8080")

        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")
        assert "score" in data, f"Response JSON missing 'score' key: {data}"
        assert isinstance(data["score"], (int, float)), f"Score must be a number, got {type(data['score'])}"
        assert data["score"] == pytest.approx(expected_dynamic_score(payload), abs=1e-12), (
            "API did not return the score produced by the bayes_classifier CLI"
        )

    assert os.path.isfile(INVOCATIONS), "No classifier invocations were recorded"
    with open(INVOCATIONS, encoding='utf-8') as f:
        calls = [json.loads(line) for line in f if line.strip()]
    received = [call.get('data') for call in calls]
    for payload in payloads:
        assert payload in received, f"API did not pass payload to bayes_classifier CLI: {payload}"
        matching = [call for call in calls if call.get('data') == payload]
        assert any('--input' in call.get('argv', []) for call in matching), "Classifier CLI was not called with --input"
TEST_EOF

if [ "$prep_ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    result=1
else
    result=0
fi

if [ -f "$BACKUP" ]; then
    cp -p "$BACKUP" "$CLI"
fi

echo "$result" > /logs/verifier/reward.txt
exit 0
