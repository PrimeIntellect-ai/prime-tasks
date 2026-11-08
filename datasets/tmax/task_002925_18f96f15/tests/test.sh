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

cp -p /home/user/datasets.ttl /tmp/datasets.ttl.verifier-backup
cp -p /app/dataset_hasher /tmp/dataset_hasher.verifier-backup

cleanup() {
    cp -p /tmp/datasets.ttl.verifier-backup /home/user/datasets.ttl || true
    cp -p /tmp/dataset_hasher.verifier-backup /app/dataset_hasher || true
}
trap cleanup EXIT

python3 - <<'PREP_EOF'
import json
import secrets
import uuid
from pathlib import Path

suffix = uuid.uuid4().hex
author1 = f"http://verifier.invalid/author/{suffix}/one"
author2 = f"http://verifier.invalid/author/{suffix}/two"
domain1 = f"http://verifier.invalid/domain/{suffix}/one"
domain2 = f"http://verifier.invalid/domain/{suffix}/two"

matches1 = [
    f"http://verifier.invalid/dataset/{suffix}/zulu",
    f"http://verifier.invalid/dataset/{suffix}/alpha",
    f"http://verifier.invalid/dataset/{suffix}/middle",
]
matches2 = [f"http://verifier.invalid/dataset/{suffix}/second-author"]
decoys = [
    f"http://verifier.invalid/dataset/{suffix}/wrong-domain",
    f"http://verifier.invalid/dataset/{suffix}/wrong-author",
]

triples = []
for dataset in matches1:
    triples.append(f"<{dataset}> <http://purl.org/dc/terms/creator> <{author1}> ; <http://purl.org/dc/terms/subject> <{domain1}> .")
for dataset in matches2:
    triples.append(f"<{dataset}> <http://purl.org/dc/terms/creator> <{author2}> ; <http://purl.org/dc/terms/subject> <{domain1}> .")
triples.append(f"<{decoys[0]}> <http://purl.org/dc/terms/creator> <{author1}> ; <http://purl.org/dc/terms/subject> <{domain2}> .")
triples.append(f"<{decoys[1]}> <http://purl.org/dc/terms/creator> <{author2}> ; <http://purl.org/dc/terms/subject> <{domain2}> .")

with open('/home/user/datasets.ttl', 'a', encoding='utf-8') as fh:
    fh.write("\n# verifier-generated records\n")
    fh.write("\n".join(triples) + "\n")

Path('/tmp/dynamic_cases.json').write_text(json.dumps({
    'author1': author1,
    'author2': author2,
    'domain1': domain1,
    'domain2': domain2,
    'matches1': matches1,
    'matches2': matches2,
    'decoys': decoys,
}), encoding='utf-8')

secret = secrets.token_bytes(32)
wrapper = f'''#!/usr/bin/env python3
import base64
import hashlib
import sys
raw = sys.stdin.buffer.read()
with open('/tmp/dataset_hasher_calls.log', 'ab') as log:
    log.write(base64.b64encode(raw) + b"\\n")
lines = [line.strip() for line in raw.decode('utf-8').splitlines() if line.strip()]
joined = "|".join(lines).encode('utf-8')
print(hashlib.sha256({secret!r} + b"\\x00" + joined).hexdigest())
'''
Path('/app/dataset_hasher').write_text(wrapper, encoding='utf-8')
Path('/app/dataset_hasher').chmod(0o755)
Path('/tmp/dataset_hasher_calls.log').write_bytes(b'')
Path('/tmp/dataset_hasher_calls.log').chmod(0o666)
PREP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import subprocess

import requests
from rdflib import Graph, URIRef

BASE_URL = "http://127.0.0.1:9090"
AUTH_HEADER = {"Authorization": "Bearer GraphOrgSecret"}
CREATOR = URIRef("http://purl.org/dc/terms/creator")
SUBJECT = URIRef("http://purl.org/dc/terms/subject")

with open('/tmp/dynamic_cases.json', encoding='utf-8') as fh:
    DYNAMIC = json.load(fh)


def get_expected_digest(uris):
    input_data = "\n".join(uris)
    if uris:
        input_data += "\n"
    result = subprocess.run(
        ["/app/dataset_hasher"],
        input=input_data.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout.decode("utf-8").strip()


def graph_results(author, domain):
    graph = Graph()
    graph.parse('/home/user/datasets.ttl', format='turtle')
    author_ref = URIRef(author)
    domain_ref = URIRef(domain)
    return sorted(
        str(dataset)
        for dataset in set(graph.subjects(CREATOR, author_ref))
        if (dataset, SUBJECT, domain_ref) in graph
    )


def clear_hasher_log():
    open('/tmp/dataset_hasher_calls.log', 'wb').close()


def hasher_inputs():
    with open('/tmp/dataset_hasher_calls.log', 'rb') as fh:
        return [base64.b64decode(line.strip()) for line in fh if line.strip()]


def assert_hasher_received(uris):
    calls = hasher_inputs()
    without_trailing_newline = "\n".join(uris).encode('utf-8')
    accepted = {without_trailing_newline}
    if uris:
        accepted.add(without_trailing_newline + b'\n')
    assert any(call in accepted for call in calls), (
        f"dataset_hasher was not invoked with the sorted result URIs; calls were {calls!r}"
    )


def test_unauthorized_missing_header():
    response = requests.get(
        f"{BASE_URL}/api/search",
        params={
            "author": "http://example.org/researcher1",
            "domain": "http://example.org/domain1",
        },
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_unauthorized_wrong_header():
    response = requests.get(
        f"{BASE_URL}/api/search",
        params={
            "author": "http://example.org/researcher1",
            "domain": "http://example.org/domain1",
        },
        headers={"Authorization": "Bearer WrongSecret"},
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_successful_search():
    response = requests.get(
        f"{BASE_URL}/api/search",
        params={
            "author": "http://example.org/researcher1",
            "domain": "http://example.org/domain1",
        },
        headers=AUTH_HEADER,
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "results" in data, "Response JSON missing 'results' key"
    assert "digest" in data, "Response JSON missing 'digest' key"
    expected_results = [
        "http://example.org/datasetA",
        "http://example.org/datasetB",
    ]
    assert data["results"] == expected_results, f"Expected results {expected_results}, got {data['results']}"
    input_str = "\n".join(expected_results)
    result = subprocess.run(
        ["/app/dataset_hasher"],
        input=input_str.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    expected_digest = result.stdout.decode("utf-8").strip()
    assert data["digest"] == expected_digest, f"Expected digest {expected_digest}, got {data['digest']}"


def test_empty_search():
    response = requests.get(
        f"{BASE_URL}/api/search",
        params={
            "author": "http://example.org/nonexistent",
            "domain": "http://example.org/domain1",
        },
        headers=AUTH_HEADER,
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "results" in data, "Response JSON missing 'results' key"
    assert "digest" in data, "Response JSON missing 'digest' key"
    assert data["results"] == [], f"Expected empty results, got {data['results']}"
    result = subprocess.run(
        ["/app/dataset_hasher"],
        input=b"",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    expected_digest = result.stdout.decode("utf-8").strip()
    assert data["digest"] == expected_digest, f"Expected digest {expected_digest}, got {data['digest']}"


def run_dynamic_case(author, domain):
    expected_results = graph_results(author, domain)
    clear_hasher_log()
    response = requests.get(
        f"{BASE_URL}/api/search",
        params={"author": author, "domain": domain},
        headers=AUTH_HEADER,
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "results" in data, "Response JSON missing 'results' key"
    assert "digest" in data, "Response JSON missing 'digest' key"
    assert data["results"] == expected_results, f"Expected results {expected_results}, got {data['results']}"
    assert_hasher_received(expected_results)
    expected_digest = get_expected_digest(expected_results)
    assert data["digest"] == expected_digest, f"Expected digest {expected_digest}, got {data['digest']}"


def test_randomized_graph_queries_and_dynamic_hasher_invocation():
    run_dynamic_case(DYNAMIC['author1'], DYNAMIC['domain1'])
    run_dynamic_case(DYNAMIC['author2'], DYNAMIC['domain1'])
    run_dynamic_case(DYNAMIC['author1'], DYNAMIC['domain2'])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
