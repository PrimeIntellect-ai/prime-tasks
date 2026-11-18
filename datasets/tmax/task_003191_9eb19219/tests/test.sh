#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
from collections import deque

HOME = "/home/user"
SOURCE = os.path.join(HOME, "audit.rs")
OUTPUT = os.path.join(HOME, "violation_path.txt")
INPUTS = [
    os.path.join(HOME, "users.csv"),
    os.path.join(HOME, "user_roles.csv"),
    os.path.join(HOME, "roles.json"),
    os.path.join(HOME, "role_resources.csv"),
]
ORIGINAL_EXPECTED = "U73,R10,R12,R14,R16,RES-999"


def derive_shortest_path():
    with open(INPUTS[0], newline="") as f:
        users = {row["user_id"] for row in csv.DictReader(f)}
    assert "U73" in users

    graph = {}
    with open(INPUTS[1], newline="") as f:
        for row in csv.DictReader(f):
            graph.setdefault(row["user_id"], []).append(row["role_id"])

    with open(INPUTS[2]) as f:
        inheritances = json.load(f)
    for role, inherited_roles in inheritances.items():
        graph.setdefault(role, []).extend(inherited_roles)

    with open(INPUTS[3], newline="") as f:
        for row in csv.DictReader(f):
            graph.setdefault(row["role_id"], []).append(row["resource_id"])

    queue = deque([("U73", ["U73"])])
    seen = {"U73"}
    while queue:
        node, path = queue.popleft()
        if node == "RES-999":
            return ",".join(path)
        for nxt in graph.get(node, []):
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, path + [nxt]))
    raise AssertionError("Generated fixture unexpectedly has no access path")


def run_program(binary, expected):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [binary], cwd=HOME, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled audit program failed with status {result.returncode}: "
        f"{result.stderr}"
    )
    assert os.path.exists(OUTPUT), f"Program did not create {OUTPUT}"
    with open(OUTPUT) as f:
        actual = f.read().strip()
    assert actual == expected, f"Expected shortest path '{expected}', got '{actual}'"


def write_generated_fixture(case_number):
    base = 10000 + secrets.randbelow(800000) + case_number * 1000000
    ids = [f"R{base + i}" for i in range(30)]
    main_len = 3 + secrets.randbelow(3)
    main = ids[:main_len]
    extra = ids[main_len]
    long_nodes = ids[main_len + 1:main_len + 1 + main_len + 1]
    dead1, dead2, orphan = ids[-3:]

    with open(INPUTS[0], "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["user_id", "name"])
        writer.writerow([f"U{900 + case_number}", "Other"])
        writer.writerow(["U73", "Alice"])

    direct_roles = [main[0], extra]
    random.SystemRandom().shuffle(direct_roles)
    with open(INPUTS[1], "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["user_id", "role_id"])
        writer.writerow(["U74", orphan])
        for role in direct_roles:
            writer.writerow(["U73", role])

    inheritance = {}
    for index in range(len(main) - 1):
        inheritance.setdefault(main[index], []).append(main[index + 1])
    inheritance.setdefault(main[0], []).append(dead1)
    inheritance[dead1] = [dead2]
    inheritance[dead2] = [dead1]
    inheritance[extra] = [long_nodes[0]]
    for index in range(len(long_nodes) - 1):
        inheritance[long_nodes[index]] = [long_nodes[index + 1]]
    inheritance[long_nodes[-1]] = [main[-1]]

    items = list(inheritance.items())
    random.SystemRandom().shuffle(items)
    with open(INPUTS[2], "w") as f:
        json.dump(dict(items), f, indent=2)
        f.write("\n")

    resource_rows = [
        [dead2, "RES-888"],
        [orphan, "RES-999"],
        [main[-1], "RES-999"],
    ]
    random.SystemRandom().shuffle(resource_rows)
    with open(INPUTS[3], "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["role_id", "resource_id"])
        writer.writerows(resource_rows)


assert os.path.exists(OUTPUT), f"Missing output file: {OUTPUT}"
with open(OUTPUT) as f:
    original_content = f.read().strip()
assert original_content == ORIGINAL_EXPECTED, (
    f"Incorrect violation path in {OUTPUT}. Expected '{ORIGINAL_EXPECTED}', "
    f"got '{original_content}'"
)
assert os.path.exists(SOURCE), f"Missing Rust source file: {SOURCE}"
assert os.path.isfile(SOURCE), f"Rust source is not a regular file: {SOURCE}"

backups = {path: open(path, "rb").read() for path in INPUTS}
original_output = open(OUTPUT, "rb").read()

try:
    with tempfile.TemporaryDirectory() as tempdir:
        binary = os.path.join(tempdir, "audit")
        compile_result = subprocess.run(
            ["rustc", SOURCE, "-o", binary],
            cwd=HOME,
            text=True,
            capture_output=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            f"rustc failed with status {compile_result.returncode}: "
            f"{compile_result.stderr}"
        )

        run_program(binary, ORIGINAL_EXPECTED)

        for case_number in range(3):
            write_generated_fixture(case_number)
            expected = derive_shortest_path()
            run_program(binary, expected)
finally:
    for path, data in backups.items():
        with open(path, "wb") as f:
            f.write(data)
    with open(OUTPUT, "wb") as f:
        f.write(original_output)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
