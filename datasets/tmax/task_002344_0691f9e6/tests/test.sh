#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess

SOURCE = "/home/user/embed.go"
DATA = "/home/user/raw_data.jsonl"
RESULT = "/home/user/result.json"
BINARY = "/tmp/embed_submission"

ORIGINAL_DATA = '''{"id": "doc1", "description": "Machine learning is a subfield of artificial intelligence."}
{"id": "doc2", "description": "Data science involves statistics and data analysis."}
{"id": "doc3", "description": "An algorithm is a step-by-step procedure for calculations."}
{"id": "doc4", "description": "Deep learning models require a lot of data and machine power."}
{"id": "doc5", "description": "Data data data science science."}
{"invalid_id": "doc6", "text": "Missing description field"}
{"id": "doc7", "description": "learning algorithm data machine science"}
'''
KEYWORDS = ["machine", "learning", "data", "science", "algorithm"]


def test_embed_go_exists():
    """Check if the Go source file was created."""
    assert os.path.exists(SOURCE), f"Go source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."


def oracle(raw, target_id):
    docs = []
    for line in raw.splitlines():
        try:
            obj = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        if not isinstance(obj, dict):
            continue
        if not isinstance(obj.get("id"), str) or not isinstance(obj.get("description"), str):
            continue
        lower = obj["description"].lower()
        docs.append((obj["id"], [lower.count(k) for k in KEYWORDS]))

    target = next(vector for doc_id, vector in docs if doc_id == target_id)
    target_mag = math.sqrt(sum(x * x for x in target))
    best_id = None
    best_score = -1.0
    for doc_id, vector in docs:
        if doc_id == target_id:
            continue
        mag = math.sqrt(sum(x * x for x in vector))
        score = 0.0 if target_mag == 0 or mag == 0 else sum(a * b for a, b in zip(target, vector)) / (target_mag * mag)
        if score > best_score:
            best_id, best_score = doc_id, score
    return best_id, float(f"{best_score:.3f}")


def description(vector):
    words = []
    for index, count in enumerate(vector):
        for occurrence in range(count):
            word = KEYWORDS[index]
            words.append(word.upper() if occurrence % 2 == 0 else word)
    random.SystemRandom().shuffle(words)
    return " :: ".join(words) if words else "unrelated words only"


def run_case(raw, target_id):
    with open(DATA, "w") as f:
        f.write(raw)
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    completed = subprocess.run([BINARY, target_id], cwd="/home/user", text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert completed.returncode == 0, f"program failed: {completed.stderr}"
    assert os.path.isfile(RESULT), "program did not generate /home/user/result.json"
    try:
        with open(RESULT) as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError("program generated invalid JSON") from exc

    expected_id, expected_score = oracle(raw, target_id)
    assert isinstance(actual, dict)
    assert actual.get("target_id") == target_id
    assert actual.get("similar_id") == expected_id
    assert isinstance(actual.get("score"), (int, float)) and not isinstance(actual.get("score"), bool)
    assert math.isclose(float(actual["score"]), expected_score, abs_tol=0.000001)


def test_program_execution_and_behavior():
    completed = subprocess.run(["go", "build", "-o", BINARY, SOURCE], cwd="/home/user",
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    assert completed.returncode == 0, f"embed.go does not compile: {completed.stderr}"

    suffix = secrets.token_hex(8)
    target = "target_" + suffix
    first = "first_" + suffix
    winner = "winner_" + suffix
    third = "third_" + suffix
    target_vector = [random.randint(1, 3) for _ in KEYWORDS]
    records = [
        {"id": first, "description": description([0, 0, 0, 0, 2])},
        {"id": target, "description": description(target_vector)},
        {"id": winner, "description": description(target_vector)},
        {"id": third, "description": description([3, 0, 1, 0, 0])},
    ]
    raw = "{malformed json\n" + "\n".join(json.dumps(x) for x in records)
    raw += '\n{"id": 99, "description": "machine"}\n{"id": "missing_description"}\n'
    run_case(raw, target)

    suffix = secrets.token_hex(8)
    target = "tie_target_" + suffix
    first = "tie_first_" + suffix
    second = "tie_second_" + suffix
    vector = [random.randint(1, 3) for _ in KEYWORDS]
    raw = "\n".join(json.dumps(x) for x in [
        {"id": target, "description": description(vector)},
        {"id": first, "description": description(vector)},
        {"id": second, "description": description([x * 2 for x in vector])},
    ]) + "\n"
    run_case(raw, target)

    suffix = secrets.token_hex(8)
    target = "zero_target_" + suffix
    first = "zero_first_" + suffix
    second = "zero_second_" + suffix
    raw = "\n".join(json.dumps(x) for x in [
        {"id": first, "description": "no relevant terms here"},
        {"id": target, "description": "also no relevant terms"},
        {"id": second, "description": "MACHINE LEARNING DATA SCIENCE ALGORITHM"},
    ]) + "\n"
    run_case(raw, target)

    # Restore the specified dataset and require the submitted program to create the final artifact.
    with open(DATA, "w") as f:
        f.write(ORIGINAL_DATA)
    if os.path.exists(RESULT):
        os.unlink(RESULT)
    completed = subprocess.run([BINARY, "doc4"], cwd="/home/user", text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert completed.returncode == 0, f"program failed on the required target: {completed.stderr}"
    assert os.path.isfile(RESULT), "program did not generate the required final result"


def test_result_json_exists():
    """Check if the result JSON file was generated."""
    file_path = "/home/user/result.json"
    assert os.path.exists(file_path), f"Result file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def test_result_json_contents():
    """Validate the contents of the result JSON file."""
    file_path = "/home/user/result.json"
    with open(file_path, "r") as f:
        text = f.read()
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        assert False, f"{file_path} does not contain valid JSON."

    assert "target_id" in data, "Result JSON is missing 'target_id' field."
    assert "similar_id" in data, "Result JSON is missing 'similar_id' field."
    assert "score" in data, "Result JSON is missing 'score' field."
    assert data["target_id"] == "doc4", f"Expected target_id to be 'doc4', got '{data['target_id']}'"
    assert data["similar_id"] == "doc1", f"Expected similar_id to be 'doc1', got '{data['similar_id']}'"
    expected_score = 0.816
    assert math.isclose(data["score"], expected_score, abs_tol=0.001), f"Expected score to be {expected_score}, got {data['score']}"
    match = re.search(r'"score"\s*:\s*-?\d+\.(\d+)(?=\s*[,}])', text)
    assert match and len(match.group(1)) == 3, "score must be written with exactly 3 decimal places"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
