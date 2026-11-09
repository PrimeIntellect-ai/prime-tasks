#!/bin/bash
mkdir -p /logs/verifier

INPUT_FILE=/home/user/data/webhooks.jsonl
OUTPUT_FILE=/home/user/workspace/valid_webhooks.jsonl
SOURCE_FILE=/home/user/workspace/filter.go
BACKUP_INPUT=""
BACKUP_OUTPUT=""

restore_files() {
    if [ -n "$BACKUP_INPUT" ] && [ -f "$BACKUP_INPUT" ]; then
        cp "$BACKUP_INPUT" "$INPUT_FILE"
    fi
    if [ -n "$BACKUP_OUTPUT" ] && [ -f "$BACKUP_OUTPUT" ]; then
        cp "$BACKUP_OUTPUT" "$OUTPUT_FILE"
    fi
}
trap restore_files EXIT

run_tests() {
cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_FILE = "/home/user/workspace/valid_webhooks.jsonl"
INPUT_FILE = "/home/user/data/webhooks.jsonl"

def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a regular file."

def test_output_file_content():
    assert os.path.exists(INPUT_FILE), f"Input file {INPUT_FILE} is missing."
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."

    with open(INPUT_FILE, 'r') as f:
        input_lines = f.readlines()

    with open(OUTPUT_FILE, 'r') as f:
        output_lines = f.readlines()

    expected_ids = [i for i in range(1, 1001) if i % 3 != 0 and i % 7 != 0]

    actual_ids = []
    for i, line in enumerate(output_lines):
        try:
            record = json.loads(line)
            actual_ids.append(record.get("id"))
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} in {OUTPUT_FILE} is not valid JSON.")

    assert actual_ids == expected_ids, (
        "The IDs in the output file do not match the expected valid IDs in the correct order. "
        "Ensure you are maintaining the original order and correctly validating the checksums."
    )

    # Check that the exact lines are preserved
    input_dict = {}
    for line in input_lines:
        try:
            record = json.loads(line)
            input_dict[record["id"]] = line
        except json.JSONDecodeError:
            pass

    for i, line in enumerate(output_lines):
        record = json.loads(line)
        expected_line = input_dict[record["id"]]
        assert line == expected_line, (
            f"The output line for id {record['id']} does not exactly match the original input line. "
            "Ensure you write the exact original JSON string with its trailing newline."
        )
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    python3 - <<'PY' || return 1
import os
p = "/home/user/workspace/filter.go"
assert os.path.isfile(p), f"{p} is missing or is not a regular file"
assert not os.path.islink(p), f"{p} must be an actual Go source file, not a symlink"
PY

cat << 'GO_EOF' > /tmp/check_submission_go.go
package main

import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)

func main() {
    path := os.Args[len(os.Args)-1]
    f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.AllErrors)
    if err != nil {
        fmt.Fprintln(os.Stderr, "filter.go is not valid Go source:", err)
        os.Exit(1)
    }
    if f.Name == nil || f.Name.Name != "main" {
        fmt.Fprintln(os.Stderr, "filter.go must declare package main")
        os.Exit(1)
    }

    importsBase64, importsCRC32, hasGoStatement := false, false, false
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil {
            continue
        }
        if p == "encoding/base64" {
            importsBase64 = true
        }
        if p == "hash/crc32" {
            importsCRC32 = true
        }
    }
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok {
            hasGoStatement = true
        }
        return true
    })

    if !importsBase64 {
        fmt.Fprintln(os.Stderr, "filter.go must use Go's encoding/base64 support")
        os.Exit(1)
    }
    if !importsCRC32 {
        fmt.Fprintln(os.Stderr, "filter.go must use Go's hash/crc32 support")
        os.Exit(1)
    }
    if !hasGoStatement {
        fmt.Fprintln(os.Stderr, "filter.go does not start any goroutines")
        os.Exit(1)
    }
}
GO_EOF

    go run /tmp/check_submission_go.go -- "$SOURCE_FILE" || return 1
    go build -o /tmp/filter_submission "$SOURCE_FILE" || return 1

    BACKUP_INPUT=$(mktemp)
    BACKUP_OUTPUT=$(mktemp)
    cp "$INPUT_FILE" "$BACKUP_INPUT" || return 1
    cp "$OUTPUT_FILE" "$BACKUP_OUTPUT" || return 1

    python3 - <<'PY' || return 1
import base64
import json
import os
import random
import secrets
import zlib

path = "/home/user/data/webhooks.jsonl"
rng = random.SystemRandom()
ids = list(range(rng.randrange(20000, 50000), rng.randrange(20000, 50000) + 160))
rng.shuffle(ids)

with open(path, "w", encoding="utf-8", newline="") as f:
    for i in range(160):
        # Strongly varying payload sizes make unordered concurrent collectors observable.
        size = [0, 1, 19, 257, 4096, 65537, 180000][i % 7]
        payload = secrets.token_bytes(size)
        encoded = base64.b64encode(payload).decode("ascii")
        checksum = zlib.crc32(payload) & 0xffffffff

        mode = i % 6
        if mode in (2, 5):
            checksum ^= 0xA5A5A5A5
        elif mode == 4:
            encoded = encoded[:-1] + "!" if encoded else "!"

        if i % 2:
            record = {"checksum": checksum, "encoded_data": encoded, "id": ids[i]}
            line = json.dumps(record, separators=(",", ":")) + "\n"
        else:
            record = {"id": ids[i], "encoded_data": encoded, "checksum": checksum}
            line = json.dumps(record, separators=(", ", ": ")) + "\n"
        f.write(line)
PY

    rm -f "$OUTPUT_FILE"
    timeout 40s /tmp/filter_submission || return 1

    python3 - <<'PY' || return 1
import base64
import json
import os
import zlib

input_path = "/home/user/data/webhooks.jsonl"
output_path = "/home/user/workspace/valid_webhooks.jsonl"
assert os.path.isfile(output_path), "The executable did not create valid_webhooks.jsonl"

with open(input_path, "r", encoding="utf-8", newline="") as f:
    input_lines = f.readlines()

expected = []
for line in input_lines:
    record = json.loads(line)
    try:
        decoded = base64.b64decode(record["encoded_data"], validate=True)
    except Exception:
        continue
    if (zlib.crc32(decoded) & 0xffffffff) == record["checksum"]:
        expected.append(line)

with open(output_path, "r", encoding="utf-8", newline="") as f:
    actual = f.readlines()

assert actual == expected, (
    "Running the submitted Go program on a fresh fixture did not produce exactly the "
    "valid original lines in input order."
)
PY
}

if run_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
