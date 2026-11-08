#!/bin/bash
set -u
mkdir -p /logs/verifier

WORKSPACE=/home/user/workspace
PIPELINE="$WORKSPACE/pipeline.go"
backup_input=$(mktemp)
testdir=$(mktemp -d)
cp "$WORKSPACE/input.csv" "$backup_input"

cleanup() {
    cp "$backup_input" "$WORKSPACE/input.csv" 2>/dev/null || true
    rm -f "$backup_input"
    rm -rf "$testdir"
}
trap cleanup EXIT

run_checks() {
    test -f "$PIPELINE" || return 1

    # Build the requested artifact.
    (cd "$WORKSPACE" && timeout 30s go build -o "$testdir/pipeline" pipeline.go) || return 1

    # Exercise ComputeEmbedding and Evaluate directly on verifier-generated cases.
    cp "$PIPELINE" "$testdir/pipeline.go" || return 1
    python3 - "$testdir" <<'PY' || return 1
import json
import os
import random
import string
import sys

testdir = sys.argv[1]
rng = random.SystemRandom()
alphabet = string.ascii_letters + string.digits + " .!?-_"
cases = []
for _ in range(12):
    text = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 40)))
    vowels = sum(ch.lower() in 'aeiou' for ch in text)
    consonants = sum(ch in string.ascii_letters and ch.lower() not in 'aeiou' for ch in text)
    cases.append((text, len(text), vowels, consonants))

values = [rng.randint(-20, 80) for _ in range(7)]
expected_average = sum(values) / len(values)

with open(os.path.join(testdir, 'pipeline_test.go'), 'w') as f:
    f.write('package main\n\nimport "testing"\n\n')
    f.write('func TestVerifierComputeEmbedding(t *testing.T) {\n')
    f.write('cases := []struct { text string; want [3]float64 }{\n')
    for text, length, vowels, consonants in cases:
        f.write('{%s, [3]float64{%d, %d, %d}},\n' %
                (json.dumps(text), length, vowels, consonants))
    f.write('}\n')
    f.write('for _, tc := range cases {\n')
    f.write('got := ComputeEmbedding(tc.text)\n')
    f.write('if len(got) != 3 { t.Fatalf("ComputeEmbedding(%q) returned length %d, want 3", tc.text, len(got)) }\n')
    f.write('for i := 0; i < 3; i++ { if got[i] != tc.want[i] { t.Fatalf("ComputeEmbedding(%q)[%d] = %v, want %v", tc.text, i, got[i], tc.want[i]) } }\n')
    f.write('}\n}\n\n')
    f.write('func TestVerifierEvaluate(t *testing.T) {\n')
    f.write('records := []Record{\n')
    for value in values:
        f.write('{Embedding: []float64{%d, 999, 999}},\n' % value)
    f.write('}\n')
    f.write('got := Evaluate(records)\n')
    f.write('want := %.17g\n' % expected_average)
    f.write('if got < want-1e-9 || got > want+1e-9 { t.Fatalf("Evaluate returned %v, want %v", got, want) }\n')
    f.write('}\n')
PY
    (cd "$testdir" && timeout 30s env GO111MODULE=off go test pipeline.go pipeline_test.go) || return 1

    # Run the built pipeline on verifier-generated CSV data, including empty
    # category_id fields, and derive the expected metrics independently.
    python3 - "$WORKSPACE/input.csv" "$testdir/expected.json" <<'PY' || return 1
import csv
import json
import random
import string
import sys

input_path, expected_path = sys.argv[1:]
rng = random.SystemRandom()
alphabet = string.ascii_letters + string.digits + " .!?-_"
rows = []
for i in range(9):
    text = ''.join(rng.choice(alphabet) for _ in range(rng.randint(2, 35)))
    category = '' if i in (1, 4, 7) else str(rng.randint(1, 20))
    rows.append([100 + i, text, category])

with open(input_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'text', 'category_id'])
    writer.writerows(rows)

with open(expected_path, 'w') as f:
    json.dump({
        'total_rows_processed': len(rows),
        'evaluation_score': sum(len(row[1]) for row in rows) / len(rows),
    }, f)
PY
    rm -f "$WORKSPACE/metrics.json"
    (cd "$WORKSPACE" && timeout 30s "$testdir/pipeline") || return 1
    python3 - "$WORKSPACE/metrics.json" "$testdir/expected.json" <<'PY' || return 1
import json
import math
import os
import sys

metrics_path, expected_path = sys.argv[1:]
assert os.path.isfile(metrics_path), 'Pipeline did not generate metrics.json'
with open(metrics_path) as f:
    actual = json.load(f)
with open(expected_path) as f:
    expected = json.load(f)
assert actual.get('total_rows_processed') == expected['total_rows_processed'], (actual, expected)
score = actual.get('evaluation_score')
assert isinstance(score, (int, float)) and not isinstance(score, bool)
assert math.isfinite(score)
assert abs(score - expected['evaluation_score']) < 1e-9, (actual, expected)
PY

    # Restore the supplied experiment input, execute the pipeline again, and
    # retain all assertions from the original verifier.
    cp "$backup_input" "$WORKSPACE/input.csv" || return 1
    rm -f "$WORKSPACE/metrics.json"
    (cd "$WORKSPACE" && timeout 30s "$testdir/pipeline") || return 1

    cat << 'TEST_EOF' > "$testdir/test_final_state.py"
import os
import json
import pytest

WORKSPACE_DIR = "/home/user/workspace"
METRICS_JSON = os.path.join(WORKSPACE_DIR, "metrics.json")

def test_metrics_json_exists():
    assert os.path.isfile(METRICS_JSON), f"Expected file {METRICS_JSON} to be generated, but it does not exist. Did you run the Go pipeline?"

def test_metrics_json_content():
    assert os.path.isfile(METRICS_JSON), f"{METRICS_JSON} is missing."

    with open(METRICS_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{METRICS_JSON} does not contain valid JSON.")

    assert "total_rows_processed" in data, "Key 'total_rows_processed' is missing from metrics.json."
    assert "evaluation_score" in data, "Key 'evaluation_score' is missing from metrics.json."

    expected_rows = 5
    actual_rows = data["total_rows_processed"]
    assert actual_rows == expected_rows, f"Expected {expected_rows} rows processed, got {actual_rows}. The bug dropping empty category_id rows might not be fixed correctly."

    expected_score = 12.8
    actual_score = data["evaluation_score"]
    assert isinstance(actual_score, (int, float)), f"Expected 'evaluation_score' to be a number, got {type(actual_score).__name__}."
    assert abs(actual_score - expected_score) < 1e-5, f"Expected evaluation_score to be {expected_score}, got {actual_score}. Check the ComputeEmbedding and Evaluate implementations."
TEST_EOF
    python3 -m pytest "$testdir/test_final_state.py" -x --tb=short || return 1
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
