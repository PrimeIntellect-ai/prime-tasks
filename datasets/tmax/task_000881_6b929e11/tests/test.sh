#!/bin/bash

mkdir -p /logs/verifier
PRIV=""

cleanup() {
    if [ -n "$PRIV" ] && [ -d "$PRIV" ]; then
        for f in employees.csv access_logs.json network.txt; do
            if [ -f "$PRIV/original-$f" ]; then
                cp "$PRIV/original-$f" "/home/user/data/$f" 2>/dev/null || true
            fi
        done
        if [ -f "$PRIV/generated-original-output.json" ]; then
            cp "$PRIV/generated-original-output.json" /home/user/violations.json 2>/dev/null || true
        elif [ -f "$PRIV/preexisting-output.json" ]; then
            cp "$PRIV/preexisting-output.json" /home/user/violations.json 2>/dev/null || true
        else
            rm -f /home/user/violations.json 2>/dev/null || true
        fi
        rm -rf "$PRIV" 2>/dev/null || true
    fi
}
trap cleanup EXIT

main() {
    # Preserve the original existence assertion and ensure the artifact is Bash syntax.
    [ -f /home/user/audit.sh ] || return 1
    bash -n /home/user/audit.sh || return 1

    PRIV=$(mktemp -d /tmp/audit-verifier.XXXXXX) || return 1
    chmod 700 "$PRIV" || return 1
    cp /home/user/data/employees.csv "$PRIV/original-employees.csv" || return 1
    cp /home/user/data/access_logs.json "$PRIV/original-access_logs.json" || return 1
    cp /home/user/data/network.txt "$PRIV/original-network.txt" || return 1
    if [ -f /home/user/violations.json ]; then
        cp /home/user/violations.json "$PRIV/preexisting-output.json" || return 1
    fi

    cat > "$PRIV/validate.py" <<'PY'
import csv
import json
import os
import sys
from collections import defaultdict, deque

output_path = "/home/user/violations.json"
assert os.path.isfile(output_path), f"The output file {output_path} was not generated."
try:
    with open(output_path, encoding="utf-8") as f:
        data = json.load(f)
except json.JSONDecodeError as exc:
    raise AssertionError(f"The file {output_path} does not contain valid JSON: {exc}")

assert isinstance(data, list), f"The JSON in {output_path} must be a list of objects."

if sys.argv[1] == "original":
    expected = [
        {
            "user_id": "u101",
            "name": "Alice Smith",
            "entry_node": "A",
            "target_node": "F",
            "path_length": 2,
        },
        {
            "user_id": "u104",
            "name": "Diana Prince",
            "entry_node": "E",
            "target_node": "F",
            "path_length": 3,
        },
    ]
    # Retain the original exact-content assertion.
    assert sorted(data, key=lambda x: x.get("user_id", "") if isinstance(x, dict) else "") == expected, \
        f"The contents of {output_path} do not match the expected violations and path lengths."
else:
    fixture_dir = sys.argv[2]
    with open(os.path.join(fixture_dir, "employees.csv"), newline="", encoding="utf-8") as f:
        employees = {row["user_id"]: row for row in csv.DictReader(f)}
    with open(os.path.join(fixture_dir, "access_logs.json"), encoding="utf-8") as f:
        logs = json.load(f)

    graph = defaultdict(set)
    with open(os.path.join(fixture_dir, "network.txt"), encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            assert len(parts) == 2
            a, b = parts
            graph[a].add(b)
            graph[b].add(a)

    def distance(start, target):
        queue = deque([(start, 0)])
        seen = {start}
        while queue:
            node, dist = queue.popleft()
            if node == target:
                return dist
            for nxt in graph[node]:
                if nxt not in seen:
                    seen.add(nxt)
                    queue.append((nxt, dist + 1))
        raise AssertionError(f"No path from {start} to {target} in generated fixture")

    expected = []
    for record in logs:
        employee = employees[record["user_id"]]
        if record["target_node"] == "F" and employee["role"] != "Admin":
            expected.append({
                "user_id": record["user_id"],
                "name": employee["name"],
                "entry_node": record["entry_node"],
                "target_node": record["target_node"],
                "path_length": distance(record["entry_node"], record["target_node"]),
            })
    expected.sort(key=lambda item: item["user_id"])
    assert data == expected, "The script did not derive the correct report from the generated input files."

# Retain and strengthen the original sortedness/schema assertions.
user_ids = []
for item in data:
    assert isinstance(item, dict), "Every array element must be an object."
    assert set(item) == {"user_id", "name", "entry_node", "target_node", "path_length"}, \
        "Each object must exactly match the required schema."
    assert all(isinstance(item[k], str) for k in ("user_id", "name", "entry_node", "target_node"))
    assert isinstance(item["path_length"], int) and not isinstance(item["path_length"], bool)
    user_ids.append(item["user_id"])
assert user_ids == sorted(user_ids), f"The array in {output_path} is not sorted alphabetically by user_id."
PY
    chmod 600 "$PRIV/validate.py" || return 1

    # Delete any prewritten answer and require the submitted script to regenerate it.
    rm -f /home/user/violations.json || return 1
    runuser -u user -- timeout 20s bash /home/user/audit.sh || return 1
    python3 "$PRIV/validate.py" original || return 1
    cp /home/user/violations.json "$PRIV/generated-original-output.json" || return 1

    # Create an unpredictable second fixture so a script hardcoding the shipped answer cannot pass.
    mkdir "$PRIV/generated" || return 1
    chmod 700 "$PRIV/generated" || return 1
    python3 - "$PRIV/generated" <<'PY'
import json
import os
import random
import secrets
import shutil
import sys

private = sys.argv[1]
nodes = list("ABCDEGHIJ")
random.SystemRandom().shuffle(nodes)
a, b, c, d, e, g, h, i, j = nodes
suffixes = [secrets.token_hex(4) for _ in range(4)]
ids = ["u" + value for value in suffixes]
names = ["Analyst " + secrets.token_hex(3) for _ in range(4)]

employees = [
    (ids[0], names[0], "User"),
    (ids[1], names[1], "Admin"),
    (ids[2], names[2], "User"),
    (ids[3], names[3], "User"),
]
random.SystemRandom().shuffle(employees)
with open(os.path.join(private, "employees.csv"), "w", encoding="utf-8", newline="") as f:
    f.write("user_id,name,role\n")
    for row in employees:
        f.write(",".join(row) + "\n")

logs = [
    {"log_id": 41, "user_id": ids[2], "entry_node": c, "target_node": "F", "timestamp": 1700000041},
    {"log_id": 42, "user_id": ids[1], "entry_node": e, "target_node": "F", "timestamp": 1700000042},
    {"log_id": 43, "user_id": ids[3], "entry_node": i, "target_node": j, "timestamp": 1700000043},
    {"log_id": 44, "user_id": ids[0], "entry_node": a, "target_node": "F", "timestamp": 1700000044},
]
random.SystemRandom().shuffle(logs)
with open(os.path.join(private, "access_logs.json"), "w", encoding="utf-8") as f:
    json.dump(logs, f)

edges = [
    (a, b), (b, "F"),                 # first violation has shortest distance 2
    (c, d), (d, e), (e, "F"),         # second violation has shortest distance 3
    (a, g), (g, e),                    # longer alternate route and a cycle
    (c, h), (h, d),
    (i, j),
]
random.SystemRandom().shuffle(edges)
with open(os.path.join(private, "network.txt"), "w", encoding="utf-8") as f:
    for left, right in edges:
        f.write(f"{left} {right}\n")

for filename in ("employees.csv", "access_logs.json", "network.txt"):
    shutil.copyfile(os.path.join(private, filename), os.path.join("/home/user/data", filename))
PY
    [ $? -eq 0 ] || return 1

    rm -f /home/user/violations.json || return 1
    runuser -u user -- timeout 20s bash /home/user/audit.sh || return 1
    python3 "$PRIV/validate.py" dynamic "$PRIV/generated" || return 1
    return 0
}

if main; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
