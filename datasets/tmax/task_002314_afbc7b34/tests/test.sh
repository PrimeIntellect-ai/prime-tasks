#!/bin/bash

mkdir -p /logs/verifier
reward=0
server_pid=""

cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

run_checks() {
    test -f /home/user/graph_restore.c || {
        echo "Missing /home/user/graph_restore.c"
        return 1
    }

    # Stop the image's static mock so the submitted program is exercised against
    # a fresh, nontrivial paginated backup generated only at verification time.
    if command -v fuser >/dev/null 2>&1; then
        fuser -k 5000/tcp >/dev/null 2>&1 || true
    fi
    pkill -f '[m]ock_backup_api.py' >/dev/null 2>&1 || true

    cat > /tmp/verification_backup_api.py <<'PY_EOF'
import json
import random
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

base = random.SystemRandom().randint(100000, 900000)
ids = {
    "deleted_user": base + 5,
    "resource_2": base + 11,
    "user_3": base + 23,
    "user_1": base + 41,
    "resource_1": base + 70,
    "deleted_resource": base + 90,
}
nonce = secrets.token_hex(8)

def node(key, status="active"):
    return {
        "type": "node",
        "id": ids[key],
        "status": status,
        "marker": nonce + "-" + key,
    }

def edge(source, target):
    return {"type": "edge", "source": ids[source], "target": ids[target]}

# Records deliberately cross page boundaries and are not in ID order.
pages = {
    1: [
        edge("user_1", "resource_1"),
        node("resource_2"),
        node("deleted_user", "deleted"),
    ],
    2: [
        node("user_1"),
        edge("deleted_user", "resource_1"),
        node("resource_1"),
        edge("user_1", "deleted_resource"),
    ],
    3: [
        edge("user_3", "resource_2"),
        node("deleted_resource", "deleted"),
        edge("user_1", "resource_2"),
        node("user_3"),
    ],
}

expected = {
    "nodes": {
        str(ids["user_1"]): "User",
        str(ids["user_3"]): "User",
        str(ids["resource_1"]): "Resource",
        str(ids["resource_2"]): "Resource",
    },
    "edges": [
        [ids["user_1"], ids["resource_1"]],
        [ids["user_1"], ids["resource_2"]],
        [ids["user_3"], ids["resource_2"]],
    ],
}
with open("/tmp/expected_graph.json", "w", encoding="utf-8") as f:
    json.dump(expected, f)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/api/chunks":
            self.send_error(404)
            return
        try:
            page = int(parse_qs(parsed.query).get("page", ["1"])[0])
        except (TypeError, ValueError):
            self.send_error(400)
            return
        body = json.dumps(pages.get(page, [])).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", 5000), Handler).serve_forever()
PY_EOF

    python3 /tmp/verification_backup_api.py >/tmp/verification_backup_api.log 2>&1 &
    server_pid=$!

    python3 - <<'PY_EOF' || return 1
import time
import urllib.request

for _ in range(50):
    try:
        with urllib.request.urlopen("http://127.0.0.1:5000/api/chunks?page=1", timeout=0.2) as response:
            if response.status == 200:
                raise SystemExit(0)
    except Exception:
        time.sleep(0.1)
raise SystemExit("verification API did not start")
PY_EOF

    gcc /home/user/graph_restore.c -o /home/user/graph_restore -lcurl -ljansson || return 1
    test -x /home/user/graph_restore || return 1

    # A pre-created or fabricated output cannot pass: remove it and execute the
    # compiled artifact against the fresh backup above.
    rm -f /home/user/restored_graph.jsonl
    timeout 30s /home/user/graph_restore || return 1

    test -f /home/user/restored_graph.jsonl || {
        echo "The output file /home/user/restored_graph.jsonl was not created."
        return 1
    }

    python3 - <<'PY_EOF' || return 1
import json

output_path = "/home/user/restored_graph.jsonl"
with open("/tmp/expected_graph.json", encoding="utf-8") as f:
    expected = json.load(f)

records = []
with open(output_path, encoding="utf-8") as f:
    for line_number, line in enumerate(f, 1):
        if not line.strip():
            raise AssertionError(f"blank line at line {line_number}")
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"invalid JSON at line {line_number}: {exc}")
        if not isinstance(record, dict):
            raise AssertionError(f"line {line_number} is not a JSON object")
        records.append(record)

if not records:
    raise AssertionError("restored graph is empty")

nodes = []
edges = []
for record in records:
    kind = record.get("type")
    if kind == "node":
        if not isinstance(record.get("id"), int):
            raise AssertionError("node has no integer id")
        if not isinstance(record.get("inferred_label"), str):
            raise AssertionError(f"node {record.get('id')} has no inferred_label")
        nodes.append(record)
    elif kind == "edge":
        if not isinstance(record.get("source"), int) or not isinstance(record.get("target"), int):
            raise AssertionError("edge endpoints must be integers")
        edges.append(record)
    else:
        raise AssertionError(f"unknown record type: {kind!r}")

node_ids_in_output_order = [record["id"] for record in nodes]
if node_ids_in_output_order != sorted(node_ids_in_output_order):
    raise AssertionError("remaining nodes are not sorted by integer id")
if len(node_ids_in_output_order) != len(set(node_ids_in_output_order)):
    raise AssertionError("duplicate node records found")

actual_nodes = {str(record["id"]): record["inferred_label"] for record in nodes}
if actual_nodes != expected["nodes"]:
    raise AssertionError(f"incorrect filtered nodes or inferred labels: {actual_nodes!r}")

actual_edges = [(record["source"], record["target"]) for record in edges]
if len(actual_edges) != len(set(actual_edges)):
    raise AssertionError("duplicate edge records found")
if set(actual_edges) != {tuple(edge) for edge in expected["edges"]}:
    raise AssertionError(f"incorrect edges or dangling edges remain: {actual_edges!r}")
PY_EOF
}

if run_checks; then
    reward=1
fi

exit 0
