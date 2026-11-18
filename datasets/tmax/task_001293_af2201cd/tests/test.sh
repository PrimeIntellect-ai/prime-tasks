#!/bin/bash
set -e
mkdir -p /logs/verifier

# Replace the fixed backends with verifier-controlled instances. The gateway must
# continue using the documented ports and fetch/validate on each request.
pkill -f '/app/log_service/app[.]py' 2>/dev/null || true
pkill -f '/app/auth_service/app[.]py' 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
import threading

import pytest
import requests
from flask import Flask, jsonify, request
from werkzeug.serving import make_server

GATEWAY_URL = "http://127.0.0.1:9000/api/audit/deadlocks"
VALID_TOKEN = "audit_sec_9942"
BAD_TOKEN = "bad_token"
DYNAMIC_TOKEN = "verify_" + secrets.token_hex(16)

ORIGINAL_LOGS = [
    {"tx": "T1", "waiting_for": "T2"},
    {"tx": "T2", "waiting_for": "T3"},
    {"tx": "T3", "waiting_for": "T1"},
    {"tx": "T4", "waiting_for": "T5"},
    {"tx": "T5", "waiting_for": "T4"},
    {"tx": "T8", "waiting_for": "T9"},
    {"tx": "T9", "waiting_for": "T10"},
    {"tx": "T10", "waiting_for": "T11"},
    {"tx": "T11", "waiting_for": "T8"},
    {"tx": "T20", "waiting_for": "T21"},
    {"tx": "T21", "waiting_for": "T20"},
    {"tx": "T30", "waiting_for": "T31"},
    {"tx": "T31", "waiting_for": "T32"},
    {"tx": "T32", "waiting_for": "T33"},
    {"tx": "T33", "waiting_for": "T34"},
    {"tx": "T34", "waiting_for": "T30"},
    {"tx": "T100", "waiting_for": "T101"},
]

state = {
    "logs": list(ORIGINAL_LOGS),
    "auth_calls": [],
    "log_calls": 0,
}

log_app = Flask("verifier_log_service")
auth_app = Flask("verifier_auth_service")

@log_app.get("/logs")
def logs_endpoint():
    state["log_calls"] += 1
    return jsonify(state["logs"])

@auth_app.post("/validate")
def validate_endpoint():
    body = request.get_json(force=True, silent=True) or {}
    token = body.get("token")
    state["auth_calls"].append(token)
    if token in {VALID_TOKEN, DYNAMIC_TOKEN}:
        return "", 200
    return "", 403


def start_server(app, port):
    server = make_server("127.0.0.1", port, app, threaded=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server


LOG_SERVER = start_server(log_app, 8001)
AUTH_SERVER = start_server(auth_app, 8002)


def expected_cycles(logs):
    adjacency = {}
    nodes = set()
    for edge in logs:
        source = edge["tx"]
        target = edge["waiting_for"]
        nodes.update((source, target))
        adjacency.setdefault(source, []).append(target)

    found = set()
    for start in nodes:
        def visit(current, path, seen):
            for nxt in adjacency.get(current, []):
                if nxt == start:
                    found.add(tuple(sorted(path)))
                elif nxt not in seen:
                    visit(nxt, path + [nxt], seen | {nxt})
        visit(start, [start], {start})
    return [list(cycle) for cycle in sorted(found)]


def get_audit(token, page, limit):
    return requests.get(
        GATEWAY_URL,
        headers={"Authorization": f"Bearer {token}"},
        params={"page": page, "limit": limit},
        timeout=5,
    )


def assert_page(response, cycles, page, limit):
    assert response.status_code == 200, (
        f"Expected HTTP 200 for valid token, got {response.status_code}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "total_deadlocks" in data, "Missing 'total_deadlocks' in response"
    assert data["total_deadlocks"] == len(cycles), (
        f"Expected {len(cycles)} total deadlocks, got {data['total_deadlocks']}"
    )
    assert "page" in data, "Missing 'page' in response"
    assert int(data["page"]) == page, f"Expected page {page}, got {data['page']}"
    assert "limit" in data, "Missing 'limit' in response"
    assert int(data["limit"]) == limit, f"Expected limit {limit}, got {data['limit']}"
    assert "data" in data, "Missing 'data' in response"
    assert isinstance(data["data"], list), "'data' should be a list"

    offset = (page - 1) * limit
    expected = cycles[offset:offset + limit]
    assert data["data"] == expected, (
        f"Expected page data {expected}, got {data['data']}"
    )
    return data


def test_unauthorized_request_is_forwarded_to_auth_service():
    state["auth_calls"].clear()
    try:
        response = get_audit(BAD_TOKEN, 1, 2)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the Gateway service at {GATEWAY_URL}: {exc}")

    assert response.status_code == 401, (
        f"Expected HTTP 401 for bad token, got {response.status_code}"
    )
    assert BAD_TOKEN in state["auth_calls"], (
        "Gateway did not forward the supplied bad token to the Auth Service"
    )


def test_missing_bearer_token_is_unauthorized():
    response = requests.get(GATEWAY_URL, params={"page": 1, "limit": 2}, timeout=5)
    assert response.status_code == 401


def test_original_data_has_correct_one_indexed_second_page():
    state["logs"] = list(ORIGINAL_LOGS)
    state["auth_calls"].clear()
    before_logs = state["log_calls"]

    try:
        response = get_audit(VALID_TOKEN, 2, 2)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the Gateway service at {GATEWAY_URL}: {exc}")

    cycles = expected_cycles(ORIGINAL_LOGS)
    data = assert_page(response, cycles, 2, 2)
    assert data["total_deadlocks"] == 5

    expected_cycle_1 = ["T20", "T21"]
    expected_cycle_2 = ["T30", "T31", "T32", "T33", "T34"]
    assert expected_cycle_1 in data["data"], (
        f"Expected cycle {expected_cycle_1} not found in page 2 data: {data['data']}"
    )
    assert expected_cycle_2 in data["data"], (
        f"Expected cycle {expected_cycle_2} not found in page 2 data: {data['data']}"
    )
    assert VALID_TOKEN in state["auth_calls"]
    assert state["log_calls"] > before_logs


def make_dynamic_logs():
    labels = ["TX_" + secrets.token_hex(5) for _ in range(24)]
    sizes = [3, 2, 4, 5, 2, 3]
    result = []
    index = 0
    for size in sizes:
        cycle = labels[index:index + size]
        index += size
        for pos, tx in enumerate(cycle):
            result.append({"tx": tx, "waiting_for": cycle[(pos + 1) % size]})

    # Include a non-cyclic chain which must not be reported.
    chain = labels[index:index + 4]
    for pos in range(len(chain) - 1):
        result.append({"tx": chain[pos], "waiting_for": chain[pos + 1]})
    return result


def test_dynamic_graph_sorting_pagination_and_fresh_fetches():
    dynamic_logs = make_dynamic_logs()
    state["logs"] = dynamic_logs
    cycles = expected_cycles(dynamic_logs)
    assert len(cycles) == 6

    state["auth_calls"].clear()
    previous_log_calls = state["log_calls"]
    for page, limit in [(1, 1), (1, 3), (2, 2), (3, 2), (2, 4), (8, 2)]:
        response = get_audit(DYNAMIC_TOKEN, page, limit)
        assert_page(response, cycles, page, limit)
        assert state["log_calls"] > previous_log_calls, (
            "Gateway did not fetch fresh data from the Log Service"
        )
        previous_log_calls = state["log_calls"]

    assert DYNAMIC_TOKEN in state["auth_calls"], (
        "Gateway did not forward the dynamically generated valid token"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
