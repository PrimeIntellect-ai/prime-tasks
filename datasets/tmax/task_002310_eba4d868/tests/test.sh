#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import pwd
import secrets
import subprocess

import pytest

OUTPUT = pathlib.Path('/home/user/top_papers.json')
SOURCE = pathlib.Path('/home/user/analyze.go')
HOME = pathlib.Path('/home/user')


def mongo_eval(js):
    proc = subprocess.run(
        ['mongosh', '--quiet', 'mongodb://127.0.0.1:27017/research', '--eval', js],
        text=True, capture_output=True, timeout=30
    )
    assert proc.returncode == 0, f'mongosh failed:\n{proc.stdout}\n{proc.stderr}'
    return proc.stdout.strip()


def mongo_json(js):
    out = mongo_eval(f'JSON.stringify({js})')
    for line in reversed(out.splitlines()):
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            pass
    pytest.fail(f'Could not parse mongosh JSON output: {out}')


def assert_original_output():
    assert OUTPUT.exists(), f'{OUTPUT} does not exist. The Go script may not have run successfully.'
    assert OUTPUT.is_file(), f'{OUTPUT} is not a file.'
    try:
        data = json.loads(OUTPUT.read_text())
    except json.JSONDecodeError:
        pytest.fail(f'{OUTPUT} does not contain valid JSON.')

    expected_data = [
        {'_id': 'P01', 'network_size': 5},
        {'_id': 'P02', 'network_size': 4},
        {'_id': 'P03', 'network_size': 2},
    ]
    assert isinstance(data, list), f'Data in {OUTPUT} must be a JSON array.'
    assert len(data) == len(expected_data), f'Expected {len(expected_data)} results, got {len(data)}.'
    for i, expected_doc in enumerate(expected_data):
        assert data[i].get('_id') == expected_doc['_id']
        assert data[i].get('network_size') == expected_doc['network_size']
        assert set(data[i]) == {'_id', 'network_size'}


def assert_requested_mongod():
    user_uid = pwd.getpwnam('user').pw_uid
    matches = []
    for procdir in pathlib.Path('/proc').iterdir():
        if not procdir.name.isdigit():
            continue
        try:
            cmd = (procdir / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
            uid = (procdir / 'status').read_text().split('Uid:', 1)[1].split()[0]
        except (OSError, IndexError):
            continue
        if 'mongod' in cmd and int(uid) == user_uid:
            matches.append(cmd)
    assert any(
        ('--dbpath /home/user/data/db' in cmd or '--dbpath=/home/user/data/db' in cmd)
        and ('--port 27017' in cmd or '--port=27017' in cmd)
        for cmd in matches
    ), 'MongoDB was not started by the current user on port 27017 with the requested dbpath.'
    assert mongo_eval("db.runCommand({ping:1}).ok") == '1', 'MongoDB is not reachable.'


def derive_expected(docs):
    by_id = {d['_id']: d for d in docs}
    results = []
    for root in docs:
        if 'Machine Learning' not in root.get('topics', []):
            continue
        seen = set()
        frontier = list(root.get('citations', []))
        for depth in range(2):
            next_frontier = []
            for paper_id in frontier:
                if paper_id in seen or paper_id not in by_id:
                    continue
                seen.add(paper_id)
                if depth < 1:
                    next_frontier.extend(by_id[paper_id].get('citations', []))
            frontier = next_frontier
        results.append({'_id': root['_id'], 'network_size': len(seen)})
    results.sort(key=lambda d: (-d['network_size'], d['_id']))
    return results[:3]


def test_complete_database_and_go_solution():
    # Preserve the original verifier's assertions on the submitted result.
    assert SOURCE.exists(), f'{SOURCE} does not exist.'
    assert SOURCE.is_file(), f'{SOURCE} is not a file.'
    assert SOURCE.stat().st_size > 0, f'{SOURCE} is empty.'
    assert_original_output()
    assert_requested_mongod()

    go_mod = HOME / 'go.mod'
    assert go_mod.is_file(), 'The required Go module was not initialized in /home/user.'

    # Use randomized identifiers so a prewritten result cannot pass. The expected
    # answer is independently derived from the imported graph.
    p = 'V' + secrets.token_hex(6)
    ids = {c: f'{p}_{c}' for c in 'ABCDEFGHIJ'}
    docs = [
        {'_id': ids['A'], 'title': 'root a', 'topics': ['Machine Learning'], 'citations': [ids['B'], ids['C']]},
        {'_id': ids['B'], 'title': 'root b', 'topics': ['Machine Learning'], 'citations': [ids['D'], ids['E']]},
        {'_id': ids['C'], 'title': 'root c', 'topics': ['Machine Learning'], 'citations': [ids['F']]},
        {'_id': ids['D'], 'title': 'd', 'topics': ['Vision'], 'citations': [ids['G'], ids['H']]},
        {'_id': ids['E'], 'title': 'e', 'topics': ['NLP'], 'citations': []},
        {'_id': ids['F'], 'title': 'f', 'topics': ['Math'], 'citations': [ids['I']]},
        {'_id': ids['G'], 'title': 'g', 'topics': ['Vision'], 'citations': []},
        {'_id': ids['H'], 'title': 'h', 'topics': ['Vision'], 'citations': []},
        {'_id': ids['I'], 'title': 'i', 'topics': ['Math'], 'citations': []},
        {'_id': ids['J'], 'title': 'root j', 'topics': ['Machine Learning'], 'citations': []},
    ]
    expected = derive_expected(docs)
    fixture = pathlib.Path('/tmp/verifier_papers.json')
    fixture.write_text(json.dumps(docs))

    mongo_eval('db.getSiblingDB("research").dropDatabase()')
    imported = subprocess.run([
        'mongoimport', '--uri=mongodb://127.0.0.1:27017/research',
        '--collection=papers', '--jsonArray', f'--file={fixture}'
    ], text=True, capture_output=True, timeout=30)
    assert imported.returncode == 0, f'mongoimport failed:\n{imported.stdout}\n{imported.stderr}'
    mongo_eval('db.setProfilingLevel(2, {slowms: 0})')

    OUTPUT.unlink(missing_ok=True)
    run = subprocess.run([
        'runuser', '-u', 'user', '--', 'env', 'HOME=/home/user',
        'GOCACHE=/home/user/.cache/go-build', 'bash', '-c',
        'cd /home/user && go run analyze.go'
    ], text=True, capture_output=True, timeout=180)
    assert run.returncode == 0, f'go run analyze.go failed:\n{run.stdout}\n{run.stderr}'
    assert OUTPUT.is_file(), 'Running analyze.go did not create top_papers.json.'

    try:
        actual = json.loads(OUTPUT.read_text())
    except json.JSONDecodeError:
        pytest.fail('The output produced by analyze.go is not valid JSON.')
    assert actual == expected, f'Aggregation result was incorrect: expected {expected}, got {actual}'
    for doc in actual:
        assert set(doc) == {'_id', 'network_size'}

    indexes = mongo_json('db.papers.getIndexes()')
    assert any(idx.get('key') == {'topics': 1} for idx in indexes), \
        'analyze.go did not create the required ascending topics index.'

    profiles = mongo_json(
        'db.system.profile.find({op:"command", "command.aggregate":"papers"})'
        '.sort({ts:-1}).limit(20).toArray()'
    )
    assert profiles, 'No aggregation of research.papers was executed by analyze.go.'

    valid_pipeline = False
    for entry in profiles:
        pipeline = entry.get('command', {}).get('pipeline', [])
        if len(pipeline) != 6:
            continue
        if [next(iter(stage), None) for stage in pipeline] != [
            '$match', '$graphLookup', '$addFields', '$sort', '$limit', '$project'
        ]:
            continue
        match = pipeline[0]['$match']
        graph = pipeline[1]['$graphLookup']
        add = pipeline[2]['$addFields']
        sort = pipeline[3]['$sort']
        limit = pipeline[4]['$limit']
        project = pipeline[5]['$project']
        match_text = json.dumps(match, sort_keys=True)
        if 'topics' not in match_text or 'Machine Learning' not in match_text:
            continue
        if not (graph.get('from') == 'papers'
                and graph.get('startWith') == '$citations'
                and graph.get('connectFromField') == 'citations'
                and graph.get('connectToField') == '_id'
                and graph.get('as') == 'citation_network'
                and graph.get('maxDepth') == 1):
            continue
        if add.get('network_size') != {'$size': '$citation_network'}:
            continue
        if sort != {'network_size': -1, '_id': 1} or limit != 3:
            continue
        if project.get('network_size') != 1 or project.get('_id', 1) != 1:
            continue
        if any(k not in {'_id', 'network_size'} for k in project):
            continue
        valid_pipeline = True
        break
    assert valid_pipeline, 'The executed aggregation did not contain the required six stages and options in order.'

    listing = subprocess.run([
        'runuser', '-u', 'user', '--', 'env', 'HOME=/home/user',
        'bash', '-c', 'cd /home/user && go list -json .'
    ], text=True, capture_output=True, timeout=60)
    assert listing.returncode == 0, f'Unable to inspect the Go module:\n{listing.stderr}'
    package = json.loads(listing.stdout)
    assert 'go.mongodb.org/mongo-driver/mongo' in package.get('Imports', []), \
        'analyze.go does not import the required MongoDB Go driver.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
