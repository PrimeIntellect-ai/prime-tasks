#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import random
import shutil
import subprocess
import tempfile
import uuid

SOURCE = "/home/user/fast_validator.go"
BINARY = "/home/user/fast_validator"
ORACLE = "/app/plan_validator"


def setup_module():
    assert os.path.exists(SOURCE), f"Missing Go source at {SOURCE}"
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file"

    if os.path.lexists(BINARY):
        if os.path.isdir(BINARY) and not os.path.islink(BINARY):
            shutil.rmtree(BINARY)
        else:
            os.unlink(BINARY)

    result = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd="/home/user",
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Go source did not compile:\n{result.stderr}"
    assert os.path.exists(BINARY), f"Missing compiled binary at {BINARY}"
    assert os.path.isfile(BINARY), f"{BINARY} is not a file"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"

    if os.path.isfile(ORACLE):
        with open(BINARY, "rb") as submitted, open(ORACLE, "rb") as reference:
            assert submitted.read() != reference.read(), "Submitted binary is byte-identical to the legacy validator"


def test_fast_validator_exists_and_executable():
    assert os.path.exists(BINARY), f"Missing compiled binary at {BINARY}"
    assert os.path.isfile(BINARY), f"{BINARY} is not a file"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"


def test_fast_validator_clean_corpus():
    clean_dir = "/eval/corpus/clean"
    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"

    failed_files = []
    for fpath in clean_files:
        result = subprocess.run([BINARY, fpath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "VALID":
            failed_files.append(os.path.basename(fpath))

    if failed_files:
        msg = f"{len(failed_files)} of {len(clean_files)} clean modified (rejected or invalid output). Offending files: {', '.join(failed_files[:10])}"
        if len(failed_files) > 10:
            msg += "..."
        assert False, msg


def test_fast_validator_evil_corpus():
    evil_dir = "/eval/corpus/evil"
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    failed_files = []
    for fpath in evil_files:
        result = subprocess.run([BINARY, fpath], capture_output=True, text=True)
        output = result.stdout.strip()
        if output != "INVALID":
            failed_files.append(os.path.basename(fpath))

    if failed_files:
        msg = f"{len(failed_files)} of {len(evil_files)} evil bypassed (accepted or invalid output). Offending files: {', '.join(failed_files[:10])}"
        if len(failed_files) > 10:
            msg += "..."
        assert False, msg


def rejected(node):
    if node.get("Node Type") == "Seq Scan" and node.get("Relation Name") == "large_archive_table":
        return True

    plans = node.get("Plans", [])
    if node.get("Node Type") == "Nested Loop" and node.get("Join Filter") is None:
        has_backup_index = any(
            isinstance(child.get("Index Name"), str)
            and child.get("Index Name").startswith("idx_backup_")
            for child in plans
        )
        if not has_backup_index:
            return True

    return any(rejected(child) for child in plans)


def expected_for(document):
    return "INVALID\n" if rejected(document[0]["Plan"]) else "VALID\n"


def random_node(rng, depth=0):
    node_type = rng.choice(["Seq Scan", "Index Scan", "Hash Join", "Nested Loop", "Aggregate"])
    node = {"Node Type": node_type, "Noise": rng.choice(["clean", "evil", "large_archive_table", "idx_backup_decoy"])}

    if node_type == "Seq Scan":
        node["Relation Name"] = rng.choice(["users", "orders", "products", "large_archive_table"])
    elif node_type == "Index Scan":
        node["Index Name"] = rng.choice(["idx_a", "idx_b", "idx_backup_" + uuid.uuid4().hex[:8], "idx_other"])
    elif node_type == "Nested Loop":
        marker = rng.randrange(3)
        if marker == 1:
            node["Join Filter"] = "(left.id = right.id)"
        elif marker == 2:
            node["Join Filter"] = None

    if depth < 4 and rng.random() < 0.78:
        node["Plans"] = [random_node(rng, depth + 1) for _ in range(rng.randint(1, 3))]
    return node


def test_unlabelled_generated_plans_follow_legacy_rules():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    documents = [
        [{"Plan": {"Node Type": "Seq Scan", "Relation Name": "users"}}],
        [{"Plan": {"Node Type": "Seq Scan", "Relation Name": "large_archive_table"}}],
        [{"Plan": {"Node Type": "Nested Loop", "Join Filter": "(a.id=b.id)", "Plans": []}}],
        [{"Plan": {"Node Type": "Nested Loop", "Plans": [{"Node Type": "Index Scan", "Index Name": "idx_backup_safe"}]}}],
        [{"Plan": {"Node Type": "Nested Loop", "Plans": [{"Node Type": "Index Scan", "Index Name": "idx_other"}]}}],
        [{"Plan": {"Node Type": "Hash Join", "Plans": [{"Node Type": "Aggregate", "Plans": [{"Node Type": "Seq Scan", "Relation Name": "large_archive_table"}]}]}}],
    ]
    documents.extend([[{"Plan": random_node(rng)}] for _ in range(140)])

    answers = [expected_for(document) for document in documents]
    assert "VALID\n" in answers and "INVALID\n" in answers

    with tempfile.TemporaryDirectory(prefix="validator_cases_" + uuid.uuid4().hex + "_") as directory:
        order = list(range(len(documents)))
        rng.shuffle(order)
        for sequence, index in enumerate(order):
            filename = uuid.uuid4().hex + f"_{sequence}.json"
            path = os.path.join(directory, filename)
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(documents[index], handle, separators=(",", ":"))

            result = subprocess.run([BINARY, path], capture_output=True, timeout=3)
            assert result.returncode == 0, f"Validator exited with {result.returncode} for generated input"
            assert result.stdout == answers[index].encode(), (
                f"Wrong output for generated input {filename}: expected {answers[index]!r}, got {result.stdout!r}"
            )


def test_invalid_json_is_rejected_at_unlabelled_paths():
    payloads = [b"", b"not json", b"{}", b"[]", b"[", b"null"]
    with tempfile.TemporaryDirectory(prefix="validator_inputs_" + uuid.uuid4().hex + "_") as directory:
        for payload in payloads:
            path = os.path.join(directory, uuid.uuid4().hex + ".json")
            with open(path, "wb") as handle:
                handle.write(payload)
            result = subprocess.run([BINARY, path], capture_output=True, timeout=3)
            assert result.returncode == 0
            assert result.stdout == b"INVALID\n"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
