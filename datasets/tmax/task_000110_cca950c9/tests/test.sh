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
import subprocess
import json
import requests
import pytest
import re
import uuid
from pathlib import Path


def test_server_source_uses_graph_lookup_and_pagination_stages():
    server_path = Path('/app/server.js')
    assert server_path.is_file(), '/app/server.js is missing'

    source = server_path.read_text(encoding='utf-8')
    source_without_comments = re.sub(r'/\*.*?\*/', '', source, flags=re.DOTALL)
    source_without_comments = re.sub(r'//[^\n]*', '', source_without_comments)

    assert re.search(r'''["']?\$graphLookup["']?\s*:''', source_without_comments), \
        'The aggregation pipeline does not contain a $graphLookup stage'
    assert not re.search(r'''["']?\$lookup["']?\s*:''', source_without_comments), \
        'The broken $lookup stage is still present'
    for stage in ('$sort', '$skip', '$limit'):
        assert re.search(rf'''["']?\{stage}["']?\s*:''', source_without_comments), \
            f'The aggregation pipeline does not contain a {stage} stage'


def test_api_subordinates_page_1():
    url = "http://127.0.0.1:8000/api/subordinates?manager_id=1&page=1&limit=3"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API on 127.0.0.1:8000: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("API response is not valid JSON")

    expected = [
        {"_id": 2, "name": "Bob", "managerId": 1},
        {"_id": 3, "name": "Charlie", "managerId": 1},
        {"_id": 4, "name": "David", "managerId": 2}
    ]

    assert len(data) == 3, f"Expected 3 records, got {len(data)}"
    for i, exp in enumerate(expected):
        assert data[i]["_id"] == exp["_id"], f"Record {i} _id mismatch"
        assert data[i]["name"] == exp["name"], f"Record {i} name mismatch"
        assert data[i]["managerId"] == exp["managerId"], f"Record {i} managerId mismatch"


def test_api_subordinates_page_2():
    url = "http://127.0.0.1:8000/api/subordinates?manager_id=1&page=2&limit=3"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API on 127.0.0.1:8000: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("API response is not valid JSON")

    expected = [
        {"_id": 5, "name": "Eve", "managerId": 2},
        {"_id": 6, "name": "Frank", "managerId": 3},
        {"_id": 7, "name": "Grace", "managerId": 3}
    ]

    assert len(data) == 3, f"Expected 3 records, got {len(data)}"
    for i, exp in enumerate(expected):
        assert data[i]["_id"] == exp["_id"], f"Record {i} _id mismatch"
        assert data[i]["name"] == exp["name"], f"Record {i} name mismatch"
        assert data[i]["managerId"] == exp["managerId"], f"Record {i} managerId mismatch"


def run_mongosh(js):
    result = subprocess.run(
        ['mongosh', 'corp', '--quiet', '--eval', js],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f'mongosh failed: {result.stderr or result.stdout}'
    return result.stdout


def fetch_subordinates(manager_id, page, limit):
    url = (
        'http://127.0.0.1:8000/api/subordinates'
        f'?manager_id={manager_id}&page={page}&limit={limit}'
    )
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f'Failed to connect to the API on 127.0.0.1:8000: {e}')
    assert response.status_code == 200, \
        f'Expected status code 200 for {url}, got {response.status_code}: {response.text}'
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f'API response is not valid JSON for {url}')
    assert isinstance(data, list), f'Expected a JSON array for {url}'
    return data


def projected(records):
    return [
        {'_id': item.get('_id'), 'name': item.get('name'), 'managerId': item.get('managerId')}
        for item in records
    ]


def test_api_traverses_fresh_hierarchy_and_honors_variable_pagination():
    base = 100000000 + (uuid.uuid4().int % 1000000000)
    token = 'verify-' + uuid.uuid4().hex[:10]
    docs = [
        {'_id': base, 'name': token + '-Root'},
        {'_id': base + 1, 'name': token + '-Zulu', 'managerId': base},
        {'_id': base + 2, 'name': token + '-Alpha', 'managerId': base},
        {'_id': base + 3, 'name': token + '-Mike', 'managerId': base + 1},
        {'_id': base + 4, 'name': token + '-Beta', 'managerId': base + 2},
        {'_id': base + 5, 'name': token + '-Omega', 'managerId': base + 3},
        {'_id': base + 6, 'name': token + '-Delta', 'managerId': base + 2},
        {'_id': base + 7, 'name': token + '-Decoy', 'managerId': base + 100}
    ]
    ids = [doc['_id'] for doc in docs]
    inserted = False

    try:
        run_mongosh('db.employees.insertMany(' + json.dumps(docs) + ')')
        inserted = True

        descendants = sorted(docs[1:7], key=lambda doc: doc['name'])

        page_one = fetch_subordinates(base, 1, 4)
        assert projected(page_one) == descendants[:4], \
            'Fresh multi-level hierarchy was not traversed and sorted correctly'

        page_two = fetch_subordinates(base, 2, 2)
        assert projected(page_two) == descendants[2:4], \
            'Pagination did not apply (page - 1) * limit with a variable limit'

        nested_expected = sorted([docs[3], docs[5]], key=lambda doc: doc['name'])
        nested = fetch_subordinates(base + 1, 1, 10)
        assert projected(nested) == nested_expected, \
            'Traversal from a different manager did not return all indirect descendants'
    finally:
        if inserted:
            run_mongosh('db.employees.deleteMany({_id: {$in: ' + json.dumps(ids) + '}})')


def test_mongodb_index_exists():
    cmd = [
        "mongosh", "corp", "--quiet", "--eval",
        "JSON.stringify(db.employees.getIndexes())"
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to execute mongosh command: {e.stderr}")

    try:
        indexes = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Failed to parse mongosh output as JSON: {result.stdout}")

    has_manager_id_index = False
    for idx in indexes:
        if "managerId" in idx.get("key", {}) and idx["key"]["managerId"] == 1:
            has_manager_id_index = True
            break

    assert has_manager_id_index, "Ascending index on managerId is missing in corp.employees"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
