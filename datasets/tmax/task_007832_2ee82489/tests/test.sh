#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import subprocess
from collections import defaultdict
from pathlib import Path

HOME = Path('/home/user')
EVENTS = HOME / 'events.ndjson'
OUTPUT = HOME / 'highly_active_mutuals.csv'
EX = 'http://example.org/'
XSD_INTEGER = 'http://www.w3.org/2001/XMLSchema#integer'

ORIGINAL_EVENTS = [
    {'user_id': 'u1', 'event_type': 'click', 'target_user': 'u2'},
    {'user_id': 'u1', 'event_type': 'click', 'target_user': 'u2'},
    {'user_id': 'u1', 'event_type': 'click', 'target_user': 'u3'},
    {'user_id': 'u1', 'event_type': 'click', 'target_user': 'u4'},
    {'user_id': 'u2', 'event_type': 'click', 'target_user': 'u1'},
    {'user_id': 'u2', 'event_type': 'click', 'target_user': 'u3'},
    {'user_id': 'u2', 'event_type': 'click', 'target_user': 'u1'},
    {'user_id': 'u3', 'event_type': 'click', 'target_user': 'u1'},
    {'user_id': 'u3', 'event_type': 'click', 'target_user': 'u2'},
    {'user_id': 'u4', 'event_type': 'click', 'target_user': 'u1'},
    {'user_id': 'u4', 'event_type': 'click', 'target_user': 'u1'},
    {'user_id': 'u4', 'event_type': 'click', 'target_user': 'u2'},
    {'user_id': 'u5', 'event_type': 'click', 'target_user': 'u4'},
    {'user_id': 'u5', 'event_type': 'click', 'target_user': 'u1'},
    {'user_id': 'u5', 'event_type': 'click', 'target_user': 'u5'},
]

DYNAMIC_EVENTS_1 = [
    {'user_id': 'alice', 'event_type': 'click', 'target_user': 'bob'},
    {'user_id': 'alice', 'event_type': 'click', 'target_user': 'bob'},
    {'user_id': 'alice', 'event_type': 'click', 'target_user': 'bob'},
    {'user_id': 'alice', 'event_type': 'purchase', 'target_user': 'zoe'},
    {'user_id': 'bob', 'event_type': 'view', 'target_user': 'alice'},
    {'user_id': 'bob', 'event_type': 'click', 'target_user': 'charlie'},
    {'user_id': 'bob', 'event_type': 'click', 'target_user': 'charlie'},
    {'user_id': 'bob', 'event_type': 'click', 'target_user': 'charlie'},
    {'user_id': 'zoe', 'event_type': 'click', 'target_user': 'alice'},
    {'user_id': 'zoe', 'event_type': 'click', 'target_user': 'alice'},
    {'user_id': 'zoe', 'event_type': 'click', 'target_user': 'alice'},
]

DYNAMIC_EVENTS_2 = [
    {'user_id': 'x2', 'event_type': 'click', 'target_user': 'x10'},
    {'user_id': 'x2', 'event_type': 'click', 'target_user': 'elsewhere'},
    {'user_id': 'x2', 'event_type': 'click', 'target_user': 'elsewhere'},
    {'user_id': 'x2', 'event_type': 'click', 'target_user': 'elsewhere'},
    {'user_id': 'x10', 'event_type': 'click', 'target_user': 'x2'},
    {'user_id': 'x10', 'event_type': 'click', 'target_user': 'other'},
    {'user_id': 'x10', 'event_type': 'click', 'target_user': 'other'},
    {'user_id': 'low', 'event_type': 'click', 'target_user': 'x2'},
    {'user_id': 'x2', 'event_type': 'view', 'target_user': 'low'},
]


def expected_rows(events):
    clicks = defaultdict(int)
    interactions = defaultdict(set)
    users = set()
    for event in events:
        user = event['user_id']
        users.add(user)
        interactions[user].add(event['target_user'])
        if event['event_type'] == 'click':
            clicks[user] += 1

    rows = [['userA', 'userB', 'clicksA', 'clicksB']]
    pairs = []
    for a in users:
        for b in interactions[a]:
            if a < b and a in interactions.get(b, set()) and clicks[a] >= 3 and clicks[b] >= 3:
                pairs.append([a, b, str(clicks[a]), str(clicks[b])])
    rows.extend(sorted(pairs, key=lambda row: (row[0], row[1])))
    return rows


def write_events(events):
    with EVENTS.open('w', encoding='utf-8') as f:
        for event in events:
            f.write(json.dumps(event, separators=(',', ':')) + '\n')


def read_output():
    assert OUTPUT.is_file(), f'Expected output file not found at {OUTPUT}'
    with OUTPUT.open('r', newline='', encoding='utf-8') as f:
        rows = [row for row in csv.reader(f) if row]
    assert rows, 'The CSV file is empty.'
    assert rows[0] == ['userA', 'userB', 'clicksA', 'clicksB'], f'CSV header is incorrect: {rows[0]}'
    return rows


def candidates():
    found = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in {'venv', '__pycache__', 'node_modules'}]
        for name in files:
            path = Path(root) / name
            if path in {EVENTS, OUTPUT} or path.stat().st_size > 2_000_000:
                continue
            is_python = path.suffix == '.py'
            if not is_python:
                try:
                    with path.open('rb') as f:
                        first = f.readline(256).lower()
                    is_python = first.startswith(b'#!') and b'python' in first
                except OSError:
                    pass
            if is_python:
                found.append(path)
    return sorted(found)


def install_instrumentation(directory):
    source = r'''
import json
import os
import rdflib

_audit_path = os.environ['ETL_AUDIT_PATH']
_original_add = rdflib.Graph.add
_original_query = rdflib.Graph.query

def _record(item):
    with open(_audit_path, 'a', encoding='utf-8') as f:
        f.write(json.dumps(item) + '\n')

def _add(self, triple):
    s, p, o = triple
    _record({'kind': 'add', 's': str(s), 'p': str(p), 'o': str(o),
             'datatype': str(getattr(o, 'datatype', '') or '')})
    return _original_add(self, triple)

def _query(self, query_object, *args, **kwargs):
    _record({'kind': 'query', 'query': str(query_object)})
    return _original_query(self, query_object, *args, **kwargs)

rdflib.Graph.add = _add
rdflib.Graph.query = _query
'''
    (directory / 'sitecustomize.py').write_text(source, encoding='utf-8')


def validate_audit(audit_path, events):
    assert audit_path.is_file(), 'No rdflib activity was observed'
    records = [json.loads(line) for line in audit_path.read_text(encoding='utf-8').splitlines() if line]
    additions = [r for r in records if r.get('kind') == 'add']
    queries = [r.get('query', '') for r in records if r.get('kind') == 'query']

    clicks = defaultdict(int)
    interactions = set()
    users = set()
    for event in events:
        users.add(event['user_id'])
        interactions.add((EX + event['user_id'], EX + event['target_user']))
        if event['event_type'] == 'click':
            clicks[event['user_id']] += 1

    click_records = [r for r in additions if r.get('p') == EX + 'clickCount']
    interaction_records = [r for r in additions if r.get('p') == EX + 'interactedWith']

    observed_clicks = {(r['s'], r['o']) for r in click_records}
    required_clicks = {(EX + user, str(clicks[user])) for user in users}
    assert required_clicks <= observed_clicks, 'The RDF graph is missing aggregated clickCount triples'
    assert all(r.get('datatype') == XSD_INTEGER for r in click_records), 'clickCount literals must use the integer datatype'

    observed_interactions = {(r['s'], r['o']) for r in interaction_records}
    assert interactions <= observed_interactions, 'The RDF graph is missing interactedWith triples'

    suitable_query = False
    for query in queries:
        lowered = query.lower()
        lexical_filter = (
            re.search(r'[?$][a-z_]\w*\s*<\s*[?$][a-z_]\w*', lowered) or
            re.search(r'str\s*\([^)]*\)\s*<\s*str\s*\([^)]*\)', lowered)
        )
        if (lowered.count('interactedwith') >= 2 and
                lowered.count('clickcount') >= 2 and
                len(re.findall(r'>=\s*3', lowered)) >= 2 and
                'filter' in lowered and lexical_filter):
            suitable_query = True
            break
    assert suitable_query, 'No SPARQL query implementing the mutual/high-activity/lexical conditions was executed'


def run_case(script, events, expected, instrumentation_dir, audit_path):
    write_events(events)
    if OUTPUT.exists():
        OUTPUT.unlink()
    if audit_path.exists():
        audit_path.unlink()

    env = os.environ.copy()
    env['ETL_AUDIT_PATH'] = str(audit_path)
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = str(instrumentation_dir) + (os.pathsep + old_pythonpath if old_pythonpath else '')
    completed = subprocess.run(
        ['python3', str(script)], cwd=str(HOME), env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=40
    )
    assert completed.returncode == 0, f'Script failed: {completed.stderr[-1000:]}'
    rows = read_output()
    assert rows == expected, f'CSV contents do not match. Expected {expected}, got {rows}'
    validate_audit(audit_path, events)


def test_complete_etl_pipeline(tmp_path):
    scripts = candidates()
    assert scripts, 'No Python script was created under /home/user'
    instrumentation_dir = tmp_path / 'instrumentation'
    instrumentation_dir.mkdir()
    install_instrumentation(instrumentation_dir)
    audit_path = tmp_path / 'rdflib-audit.jsonl'

    failures = []
    winner = None
    try:
        for script in scripts:
            try:
                run_case(script, DYNAMIC_EVENTS_1, expected_rows(DYNAMIC_EVENTS_1), instrumentation_dir, audit_path)
                run_case(script, DYNAMIC_EVENTS_2, expected_rows(DYNAMIC_EVENTS_2), instrumentation_dir, audit_path)

                # Preserve the original verifier's exact assertion, now after executing the artifact.
                original_expected = [
                    ['userA', 'userB', 'clicksA', 'clicksB'],
                    ['u1', 'u2', '4', '3'],
                    ['u1', 'u4', '4', '3'],
                ]
                run_case(script, ORIGINAL_EVENTS, original_expected, instrumentation_dir, audit_path)
                winner = script
                break
            except Exception as exc:
                failures.append(f'{script}: {exc}')
        assert winner is not None, 'No Python script completed the required pipeline:\n' + '\n'.join(failures)
    finally:
        write_events(ORIGINAL_EVENTS)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
