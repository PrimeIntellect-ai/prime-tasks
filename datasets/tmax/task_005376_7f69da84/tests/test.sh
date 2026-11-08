#!/bin/bash
mkdir -p /logs/verifier

# Restore the schema used to generate the task so oracle-derived expectations
# cannot be trivialized by modifying the writable resource.
cat > /home/user/target_schema.json <<'SCHEMA_EOF'
["_id", "total_sales", "customer_name", "timestamp"]
SCHEMA_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import subprocess
import tempfile

BINARY_PATH = "/home/user/pipeline_guard/target/release/pipeline_guard"
ORACLE_PATH = "/app/agg_oracle"
CLEAN_CORPUS = "/home/user/corpora/clean"
EVIL_CORPUS = "/home/user/corpora/evil"
SCHEMA = ["_id", "total_sales", "customer_name", "timestamp"]


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fp:
        for block in iter(lambda: fp.read(65536), b""):
            h.update(block)
    return h.digest()


def oracle_accepts(payload):
    with tempfile.NamedTemporaryFile(prefix="pipeline-", suffix=".json", delete=False) as fp:
        fp.write(payload)
        path = fp.name
    try:
        result = subprocess.run(
            [ORACLE_PATH, path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
        return result.returncode == 0
    finally:
        os.unlink(path)


def candidate_accepts(payload):
    try:
        result = subprocess.run(
            [BINARY_PATH],
            input=payload,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("pipeline_guard timed out")
    return result.returncode == 0


def check_payload(payload, description):
    expected = oracle_accepts(payload)
    actual = candidate_accepts(payload)
    assert actual == expected, (
        f"Mismatch for {description}: oracle accepted={expected}, "
        f"pipeline_guard accepted={actual}; input={payload[:500]!r}"
    )


def encoded(pipeline):
    return json.dumps(pipeline, separators=(",", ":")).encode()


def project(keys=None):
    if keys is None:
        keys = SCHEMA
    return {"$project": {key: 1 for key in keys}}


def test_binary_exists_and_executable_and_is_not_oracle_copy():
    assert os.path.exists(BINARY_PATH), f"Binary not found at {BINARY_PATH}"
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"
    assert digest(BINARY_PATH) != digest(ORACLE_PATH), "Submission is byte-identical to agg_oracle"


def test_shipped_corpora_against_oracle():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus directory {CLEAN_CORPUS} not found"
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus directory {EVIL_CORPUS} not found"

    clean_files = sorted(
        os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS)
        if os.path.isfile(os.path.join(CLEAN_CORPUS, f))
    )
    evil_files = sorted(
        os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS)
        if os.path.isfile(os.path.join(EVIL_CORPUS, f))
    )
    assert clean_files, "Clean corpus is empty"
    assert evil_files, "Evil corpus is empty"

    for path in clean_files:
        with open(path, "rb") as fp:
            check_payload(fp.read(), f"shipped clean corpus file {os.path.basename(path)}")

    for path in evil_files:
        with open(path, "rb") as fp:
            payload = fp.read()
        assert not oracle_accepts(payload), f"Shipped evil file is unexpectedly accepted: {path}"
        check_payload(payload, f"shipped evil corpus file {os.path.basename(path)}")


def test_structural_edge_cases_against_oracle():
    cases = [
        [project()],
        [{"$match": {"status": "A"}}, project()],
        [{"$match": {}}, {"$group": {"_id": "$x"}}, project()],
        [{"$group": {"_id": "$x"}}, project()],
        [{"$group": {}}, {"$match": {}}, project()],
        [{"$lookup": {"from": "a"}}, {"$lookup": {"from": "b"}}, project()],
        [{"$lookup": {"from": "a"}}, {"$lookup": {"from": "b"}}, {"$lookup": {"from": "c"}}, project()],
        [{"$lookup": {"from": "a"}}, {"$unwind": "$a"}, project()],
        [{"$lookup": {"from": "a"}}, {"$match": {}}, {"$unwind": "$a"}, project()],
        [{"$lookup": {"from": "a"}}, {"$project": {"temporary": 1}}, {"$unwind": "$a"}, project()],
        [project(SCHEMA[:-1])],
        [project(SCHEMA + ["extra"])],
        [{"$match": {}}],
        [],
    ]
    for index, pipeline in enumerate(cases):
        check_payload(encoded(pipeline), f"structural edge case {index}")

    malformed = [b"", b"null", b"{}", b"not-json", b"[", b"42", b'[{"$match":}]']
    for index, payload in enumerate(malformed):
        check_payload(payload, f"malformed input {index}")


def test_generated_pipelines_against_oracle():
    rng = random.SystemRandom()

    # Generate many known-valid shapes so acceptance cannot be avoided by a
    # program that merely rejects arbitrary inputs.
    for index in range(100):
        pipeline = []
        has_match = False
        lookup_count = 0
        for _ in range(rng.randrange(0, 8)):
            choice = rng.choice(["match", "group", "lookup", "unwind", "sort", "limit"])
            if choice == "match":
                pipeline.append({"$match": {"v": rng.randrange(1000)}})
                has_match = True
            elif choice == "group":
                if not has_match:
                    pipeline.append({"$match": {"seed": rng.randrange(1000)}})
                    has_match = True
                pipeline.append({"$group": {"_id": "$item"}})
            elif choice == "lookup" and lookup_count < 2:
                pipeline.append({"$lookup": {"from": f"c{rng.randrange(1000)}"}})
                lookup_count += 1
            elif choice == "unwind":
                if pipeline and "$lookup" in pipeline[-1]:
                    pipeline.append({"$match": {"separator": True}})
                    has_match = True
                pipeline.append({"$unwind": "$items"})
            elif choice == "sort":
                pipeline.append({"$sort": {"timestamp": rng.choice([-1, 1])}})
            elif choice == "limit":
                pipeline.append({"$limit": rng.randrange(1, 100)})
        pipeline.append(project())
        payload = json.dumps(pipeline, indent=rng.choice([None, 1, 2])).encode()
        assert oracle_accepts(payload), f"Generated valid case {index} was not valid"
        check_payload(payload, f"generated valid case {index}")

    # Unconstrained combinations are labeled by executing the oracle rather
    # than trusting directory names or hand-written expected labels.
    stage_kinds = ["match", "group", "lookup", "unwind", "sort", "project"]
    for index in range(250):
        pipeline = []
        for _ in range(rng.randrange(0, 10)):
            kind = rng.choice(stage_kinds)
            if kind == "match":
                stage = {"$match": {f"f{rng.randrange(5)}": rng.randrange(20)}}
            elif kind == "group":
                stage = {"$group": {"_id": f"$f{rng.randrange(5)}"}}
            elif kind == "lookup":
                stage = {"$lookup": {"from": f"c{rng.randrange(5)}"}}
            elif kind == "unwind":
                stage = {"$unwind": f"$f{rng.randrange(5)}"}
            elif kind == "sort":
                stage = {"$sort": {f"f{rng.randrange(5)}": rng.choice([-1, 1])}}
            else:
                projection_kind = rng.randrange(3)
                if projection_kind == 0:
                    stage = project()
                elif projection_kind == 1:
                    stage = project(SCHEMA[:-1])
                else:
                    stage = project(SCHEMA + [f"extra{rng.randrange(5)}"])
            pipeline.append(stage)

        ending = rng.randrange(4)
        if ending == 0:
            pipeline.append(project())
        elif ending == 1:
            pipeline.append(project(SCHEMA[:-1]))
        elif ending == 2:
            pipeline.append({"$match": {"tail": True}})

        payload = json.dumps(pipeline, separators=(",", ":")).encode()
        check_payload(payload, f"random oracle-derived case {index}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
