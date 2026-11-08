#!/bin/bash
mkdir -p /logs/verifier

if bash -euo pipefail <<'VERIFY_EOF'
project=/home/user/etl_pipeline
json_path=/home/user/output/experiment.json

# Require and execute the requested Rust project rather than trusting a prewritten JSON file.
test -d "$project"
test ! -L "$project"
test -f "$project/Cargo.toml"
test ! -L "$project/Cargo.toml"
test -f "$project/src/main.rs"
test ! -L "$project/src/main.rs"
test -d /home/user/model
test ! -L /home/user/model
test -d /home/user/data
test ! -L /home/user/data
test -d /home/user/output
test ! -L /home/user/output

work=$(mktemp -d /root/etl-verifier.XXXXXX)
cp /home/user/model/weights.csv "$work/weights.csv"
cp -a /home/user/data "$work/data"

restore() {
    rm -rf /home/user/data
    cp -a "$work/data" /home/user/data
    cp "$work/weights.csv" /home/user/model/weights.csv
    if [ -f "$work/experiment.json" ]; then
        mkdir -p /home/user/output
        cp "$work/experiment.json" /home/user/output/experiment.json
    fi
    rm -rf "$work"
}
trap restore EXIT

rm -f "$json_path"
timeout 120s runuser -u user -- env HOME=/home/user cargo run --quiet --manifest-path "$project/Cargo.toml"
test -f "$json_path"

cat > "$work/test_fixed.py" <<'PY_EOF'
import os
import json
import math
import pytest

def test_experiment_json_exists():
    json_path = "/home/user/output/experiment.json"
    assert os.path.isfile(json_path), f"Expected output file {json_path} does not exist."

def test_experiment_json_content():
    json_path = "/home/user/output/experiment.json"
    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert "best_match_file" in data, "Missing 'best_match_file' in JSON output."
    assert "query_vector" in data, "Missing 'query_vector' in JSON output."
    assert "doc_vectors" in data, "Missing 'doc_vectors' in JSON output."

    assert data["best_match_file"] == "doc1.txt", f"Expected best_match_file to be 'doc1.txt', got {data['best_match_file']}."

    expected_query = [1.0, 2.0]
    assert len(data["query_vector"]) == 2, "query_vector should have 2 elements."
    for actual, expected in zip(data["query_vector"], expected_query):
        assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5), \
            f"Query vector mismatch: expected {expected_query}, got {data['query_vector']}"

    expected_docs = {
        "doc1.txt": [2.5, 2.5],
        "doc2.txt": [-1.5, -1.5],
        "doc3.txt": [0.0, 1.0]
    }

    doc_vectors = data["doc_vectors"]
    for doc, expected_vec in expected_docs.items():
        assert doc in doc_vectors, f"Missing {doc} in doc_vectors."
        actual_vec = doc_vectors[doc]
        assert len(actual_vec) == 2, f"Vector for {doc} should have 2 elements."
        for actual, expected in zip(actual_vec, expected_vec):
            assert math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-5), \
                f"Vector mismatch for {doc}: expected {expected_vec}, got {actual_vec}"
PY_EOF
python3 -m pytest "$work/test_fixed.py" -x --tb=short
cp "$json_path" "$work/experiment.json"

# Replace the fixture with randomized weights and different documents. The oracle is
# independently derived and kept under /root, where the submitted program cannot read it.
python3 - "$work/expected_dynamic.json" <<'PY_EOF'
import json
import math
import os
import secrets
import shutil
import sys

expected_path = sys.argv[1]
rng = secrets.SystemRandom()
words = ["brown", "fox", "north", "south", "east", "west"]
documents = {
    "candidate_a.txt": "brown fox unseen",
    "candidate_b.txt": "brown brown north",
    "candidate_c.txt": "fox south east west",
}

def add(a, b):
    return [a[0] + b[0], a[1] + b[1]]

def embed(text, weights):
    result = [0.0, 0.0]
    for token in text.split():
        result = add(result, weights.get(token, [0.0, 0.0]))
    return result

def cosine(a, b):
    na = math.hypot(*a)
    nb = math.hypot(*b)
    if na == 0.0 or nb == 0.0:
        return 0.0
    return (a[0] * b[0] + a[1] * b[1]) / (na * nb)

while True:
    weights = {word: [rng.randint(-90, 90) / 10.0, rng.randint(-90, 90) / 10.0]
               for word in words}
    query = embed("brown fox", weights)
    if math.hypot(*query) < 0.5:
        continue
    vectors = {name: embed(text, weights) for name, text in documents.items()}
    scores = {name: cosine(query, vec) for name, vec in vectors.items()}
    ordered = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    if ordered[0][0] == "candidate_a.txt" and ordered[0][1] - ordered[1][1] > 1e-6:
        break

with open("/home/user/model/weights.csv", "w") as f:
    for word in words:
        f.write(f"{word},{weights[word][0]:.1f},{weights[word][1]:.1f}\n")

shutil.rmtree("/home/user/data")
os.mkdir("/home/user/data", 0o755)
for name, text in documents.items():
    with open(os.path.join("/home/user/data", name), "w") as f:
        f.write(text + "\n")
with open("/home/user/data/ignored.md", "w") as f:
    f.write("brown fox\n")

expected = {
    "best_match_file": ordered[0][0],
    "query_vector": query,
    "doc_vectors": vectors,
}
with open(expected_path, "w") as f:
    json.dump(expected, f)
os.chmod(expected_path, 0o600)
PY_EOF

rm -f "$json_path"
timeout 120s runuser -u user -- env HOME=/home/user cargo run --quiet --manifest-path "$project/Cargo.toml"
test -f "$json_path"

python3 - "$work/expected_dynamic.json" "$json_path" <<'PY_EOF'
import json
import math
import os
import sys

expected_path, actual_path = sys.argv[1:]
with open(expected_path) as f:
    expected = json.load(f)
with open(actual_path) as f:
    actual = json.load(f)

for key in ("best_match_file", "query_vector", "doc_vectors"):
    assert key in actual, f"Missing {key!r} in dynamic output"
assert actual["best_match_file"] == expected["best_match_file"], (
    f"Wrong dynamic best match: {actual['best_match_file']!r}"
)
assert set(actual["doc_vectors"]) == set(expected["doc_vectors"]), (
    "doc_vectors must contain exactly the dynamically supplied .txt files"
)

def check_vector(label, got, want):
    assert isinstance(got, list) and len(got) == 2, f"{label} must be a two-element array"
    for value, target in zip(got, want):
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f"{label} contains a non-number"
        assert math.isfinite(value), f"{label} contains a non-finite number"
        assert math.isclose(value, target, rel_tol=1e-5, abs_tol=1e-5), (
            f"{label}: expected {want}, got {got}"
        )

check_vector("query_vector", actual["query_vector"], expected["query_vector"])
for name, vector in expected["doc_vectors"].items():
    check_vector(f"doc_vectors[{name!r}]", actual["doc_vectors"][name], vector)
PY_EOF
VERIFY_EOF
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
