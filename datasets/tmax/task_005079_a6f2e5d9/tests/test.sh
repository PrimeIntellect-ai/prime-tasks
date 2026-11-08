#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import string
import subprocess
import pytest


def generate_random_string(min_len=3, max_len=20):
    length = random.randint(min_len, max_len)
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def generate_fuzz_input():
    num_fields = random.randint(1, 5)
    fields = [generate_random_string() for _ in range(num_fields)]
    data = {
        "source_collection": generate_random_string(),
        "match_status": generate_random_string(),
        "join_collection": generate_random_string(),
        "join_local_field": generate_random_string(),
        "join_foreign_field": generate_random_string(),
        "join_as": generate_random_string(),
        "fields": fields
    }
    return json.dumps(data)


def test_compiler_bug_fixed():
    path = "/app/mongogen-audit-0.5.0/mongogen/compiler.py"
    assert os.path.isfile(path), f"Compiler file missing: {path}"
    with open(path, "r") as f:
        content = f.read()
    assert '"localField": "_id"' not in content, f"Bug still present in {path}: localField is hardcoded to '_id'"
    assert '"localField": local' in content or "'localField': local" in content or "localField" in content, f"Bug fix not properly implemented in {path}"

    from mongogen.compiler import PipelineBuilder
    local_field = "dynamic_transaction_key"
    builder = PipelineBuilder("audit_source")
    builder.add_lookup("accounts", local_field, "account_key", "joined_accounts")
    pipeline = json.loads(builder.to_json())
    assert pipeline == [{
        "$lookup": {
            "from": "accounts",
            "localField": local_field,
            "foreignField": "account_key",
            "as": "joined_accounts"
        }
    }], "PipelineBuilder.add_lookup does not use the supplied local field"


def test_build_pipeline_script_exists():
    path = "/home/user/build_pipeline.py"
    assert os.path.isfile(path), f"Agent script missing: {path}"


def test_fuzz_equivalence():
    agent_script = "/home/user/build_pipeline.py"
    oracle_script = "/tests/build_pipeline_oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing from tests: {oracle_script}"

    random.seed(42)
    num_iterations = 500

    for i in range(num_iterations):
        input_json = generate_fuzz_input()

        agent_proc = subprocess.run(
            ["python3", agent_script, input_json],
            capture_output=True,
            text=True
        )
        oracle_proc = subprocess.run(
            ["python3", oracle_script, input_json],
            capture_output=True,
            text=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed on input: {input_json}\nError: {agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle script failed on input: {input_json}\nError: {oracle_proc.stderr}"

        try:
            agent_output = json.loads(agent_proc.stdout.strip())
        except json.JSONDecodeError:
            pytest.fail(f"Agent output is not valid JSON on input: {input_json}\nOutput: {agent_proc.stdout}")

        try:
            oracle_output = json.loads(oracle_proc.stdout.strip())
        except json.JSONDecodeError:
            pytest.fail(f"Oracle output is not valid JSON on input: {input_json}\nOutput: {oracle_proc.stdout}")

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i+1}.\n"
            f"Input: {input_json}\n"
            f"Agent output: {agent_output}\n"
            f"Oracle output: {oracle_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
