#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import math
import os
import pwd
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from pymongo import MongoClient

HOME = Path('/home/user')
DB_NAME = 'logistics'
COLL_NAME = 'processed_orders'


def expected_documents():
    graph = {}
    with open(HOME / 'routes.csv', newline='') as f:
        for row in csv.DictReader(f):
            graph.setdefault(row['source'], []).append((row['destination'], float(row['cost'])))

    def shortest(source, destination):
        queue = [(0.0, source, [source])]
        best = {}
        while queue:
            cost, node, path = heapq.heappop(queue)
            if node in best and best[node] <= cost:
                continue
            best[node] = cost
            if node == destination:
                return path, float(cost)
            for neighbor, edge_cost in graph.get(node, []):
                heapq.heappush(queue, (cost + edge_cost, neighbor, path + [neighbor]))
        return [], -1.0

    result = []
    with open(HOME / 'orders.csv', newline='') as f:
        for row in csv.DictReader(f):
            path, cost = shortest(row['origin'], row['destination'])
            result.append({
                'order_id': int(row['order_id']),
                'origin': row['origin'],
                'destination': row['destination'],
                'path': path,
                'total_cost': cost,
            })
    return result


def assert_mongodb_initialized(client):
    client.admin.command('ping')
    status = client.admin.command('serverStatus')
    pid = int(status['pid'])
    proc = Path('/proc') / str(pid)
    assert proc.exists(), 'The MongoDB server process is not running.'

    cmdline = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
    assert 'mongod' in cmdline, 'The service on port 27017 is not mongod.'
    assert '/home/user/mongo_data' in cmdline, 'mongod was not started with /home/user/mongo_data as its dbpath.'

    uid_line = next(line for line in (proc / 'status').read_text().splitlines() if line.startswith('Uid:'))
    process_uid = int(uid_line.split()[1])
    assert process_uid == pwd.getpwnam('user').pw_uid, 'mongod is not running as the current task user.'
    assert (HOME / 'mongo_data').is_dir(), 'The required MongoDB data directory does not exist.'


def python_scripts():
    scripts = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d != 'mongo_data' and not d.startswith('.')]
        for name in files:
            path = Path(root) / name
            if path.suffix == '.py' and path.is_file():
                scripts.append(path)
    assert len(scripts) >= 2, 'Two Python scripts for ingestion and aggregation are required.'
    return sorted(scripts)


def run_script(path):
    completed = subprocess.run(
        ['runuser', '-u', 'user', '--', 'env', 'HOME=/home/user', 'python3', str(path)],
        cwd=str(HOME), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=40
    )
    return completed


def assert_documents_are_correct(collection, expected):
    actual = list(collection.find({}, {'_id': 0}).sort('order_id', 1))
    assert len(actual) == len(expected), f'Expected {len(expected)} processed orders, got {len(actual)}.'
    for got, want in zip(actual, expected):
        assert set(got) == {'order_id', 'origin', 'destination', 'path', 'total_cost'}, \
            f'Processed order has incorrect fields: {got}'
        assert isinstance(got['order_id'], int) and not isinstance(got['order_id'], bool)
        assert isinstance(got['origin'], str)
        assert isinstance(got['destination'], str)
        assert isinstance(got['path'], list) and all(isinstance(x, str) for x in got['path'])
        assert isinstance(got['total_cost'], float), 'total_cost must be stored as a float.'
        assert got['order_id'] == want['order_id']
        assert got['origin'] == want['origin']
        assert got['destination'] == want['destination']
        assert got['path'] == want['path'], f"Order {want['order_id']} has path {got['path']}, expected {want['path']}"
        assert math.isclose(got['total_cost'], want['total_cost'], rel_tol=1e-9, abs_tol=1e-9)


def find_required_stages(pipeline):
    names = ['$match', '$group', '$sort', '$skip', '$limit']
    positions = {}
    for name in names:
        matches = [i for i, stage in enumerate(pipeline) if isinstance(stage, dict) and name in stage]
        assert matches, f'Aggregation pipeline is missing required {name} stage.'
        positions[name] = matches[0]
    assert [positions[n] for n in names] == sorted(positions.values()), 'Aggregation stages are in the wrong order.'

    group = pipeline[positions['$group']]['$group']
    assert group.get('_id') == '$origin', 'Aggregation must group by origin.'
    assert group.get('average_cost') == {'$avg': '$total_cost'}, 'average_cost must use $avg on total_cost.'
    assert group.get('successful_orders') in ({'$sum': 1}, {'$count': {}}), \
        'successful_orders must count the grouped documents.'

    sort = pipeline[positions['$sort']]['$sort']
    assert sort.get('average_cost') == -1, 'Results must be sorted descending by average_cost.'
    assert pipeline[positions['$skip']]['$skip'] == 1, 'Aggregation must skip the first record.'
    assert pipeline[positions['$limit']]['$limit'] == 3, 'Aggregation must limit output to three records.'
    return pipeline[positions['$match']]


def assert_match_filters_minus_one(db, match_stage):
    probe = db['verifier_match_probe']
    probe.drop()
    probe.insert_many([
        {'marker': 'failed', 'order_id': 9001, 'origin': 'Probe', 'destination': 'X', 'path': [], 'total_cost': -1.0},
        {'marker': 'success', 'order_id': 9002, 'origin': 'Probe', 'destination': 'X', 'path': ['Probe', 'X'], 'total_cost': 1.0},
    ])
    remaining = list(probe.aggregate([match_stage]))
    markers = {doc.get('marker') for doc in remaining}
    probe.drop()
    assert 'failed' not in markers and 'success' in markers, \
        'The $match stage must exclude total_cost == -1 while retaining successful orders.'


def assert_report_original_checks():
    file_path = '/home/user/final_report.json'
    assert os.path.isfile(file_path), f'File {file_path} does not exist. Did you export the results?'
    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {file_path} is not valid JSON.'

    assert isinstance(data, list), 'The JSON output should be an array of objects.'
    assert len(data) == 3, f'Expected exactly 3 records in the final report after pagination, got {len(data)}.'
    expected = [
        {'_id': 'F', 'average_cost': 30.0, 'successful_orders': 1},
        {'_id': 'C', 'average_cost': 24.0, 'successful_orders': 2},
        {'_id': 'B', 'average_cost': 20.0, 'successful_orders': 1},
    ]
    for i in range(3):
        assert set(data[i]) == {'_id', 'average_cost', 'successful_orders'}
        actual_id = data[i].get('_id')
        assert actual_id == expected[i]['_id'], f"Record {i} expected _id '{expected[i]['_id']}', got '{actual_id}'"
        actual_cost = data[i].get('average_cost')
        assert actual_cost is not None, f"Record {i} missing 'average_cost'"
        assert isinstance(actual_cost, float), 'average_cost must be a float.'
        assert math.isclose(actual_cost, expected[i]['average_cost'], rel_tol=1e-5)
        assert data[i].get('successful_orders') == expected[i]['successful_orders']


def test_complete_workflow():
    client = MongoClient('mongodb://127.0.0.1:27017', serverSelectionTimeoutMS=4000)
    assert_mongodb_initialized(client)
    db = client[DB_NAME]
    collection = db[COLL_NAME]
    expected = expected_documents()
    scripts = python_scripts()

    ingestion_script = None
    for candidate in scripts:
        collection.delete_many({})
        result = run_script(candidate)
        if result.returncode != 0:
            continue
        try:
            assert_documents_are_correct(collection, expected)
            ingestion_script = candidate
            break
        except AssertionError:
            continue
    assert ingestion_script is not None, 'No submitted Python script populated processed_orders correctly when executed.'

    aggregation_script = None
    recorded_pipeline = None
    for candidate in scripts:
        if candidate == ingestion_script:
            continue
        collection.delete_many({})
        ingest_result = run_script(ingestion_script)
        if ingest_result.returncode != 0:
            continue
        try:
            assert_documents_are_correct(collection, expected)
        except AssertionError:
            continue

        report = HOME / 'final_report.json'
        if report.exists():
            report.unlink()
        db.command('profile', 0)
        db['system.profile'].drop()
        db.command('profile', 2)
        started = datetime.now(timezone.utc)
        result = run_script(candidate)
        db.command('profile', 0)
        if result.returncode != 0:
            continue

        entries = list(db['system.profile'].find({
            'ts': {'$gte': started},
            'command.aggregate': COLL_NAME,
        }))
        if not entries:
            continue
        for entry in entries:
            pipeline = entry.get('command', {}).get('pipeline')
            if not isinstance(pipeline, list):
                continue
            try:
                match_stage = find_required_stages(pipeline)
                assert_match_filters_minus_one(db, match_stage)
                assert_documents_are_correct(collection, expected)
                assert_report_original_checks()
                aggregation_script = candidate
                recorded_pipeline = pipeline
                break
            except AssertionError:
                continue
        if aggregation_script is not None:
            break

    assert aggregation_script is not None, \
        'No distinct second Python script executed the required MongoDB aggregation pipeline and exported its result.'
    assert recorded_pipeline is not None


if __name__ == '__main__':
    test_complete_workflow()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
