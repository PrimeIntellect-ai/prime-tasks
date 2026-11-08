#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import sys
import pytest

def generate_fuzz_inputs(n=500, seed=42):
    random.seed(seed)
    entities = ["Paper", "Author", "Grant"]
    rel_fields = ["author_id", "grant_id", "institution_id"]
    scalar_fields = ["year_published", "amount", "name"]
    possible_returns = ["title", "doi", "name", "id", "amount"]

    inputs = []
    for _ in range(n):
        entity = random.choice(entities)
        filters = {}
        for rf in rel_fields:
            if random.random() < 0.3:
                filters[rf] = f"VAL_{random.randint(1, 100)}"
        for sf in scalar_fields:
            if random.random() < 0.3:
                filters[sf] = random.choice([2020, 2021, 2022, "Some Name", 10000])

        # Ensure at least one filter
        if not filters:
            filters["year_published"] = 2022

        k = random.randint(1, len(possible_returns))
        return_fields = random.sample(possible_returns, k)

        obj = {
            "entity": entity,
            "filters": filters,
            "return_fields": return_fields
        }
        inputs.append(json.dumps(obj))
    return inputs

def test_pycypher_ast_fixed():
    """
    Verify that the vendored package is fixed and can parse parameterized queries.
    """
    vendored_path = "/app/pycypher-ast-1.2.0"
    if vendored_path not in sys.path:
        sys.path.insert(0, vendored_path)

    try:
        from pycypher_ast import parse
    except ImportError as e:
        pytest.fail(f"Could not import pycypher_ast.parse: {e}")

    query = "MATCH (n) WHERE n.val = $test RETURN n"
    try:
        ast = parse(query)
    except Exception as e:
        pytest.fail(f"AST parsing failed on parameterized query. The bug is likely not fixed. Error: {e}")

def test_schema_mapper_fuzz_equivalence():
    """
    Verify the agent's schema_mapper.py behaves bit-exactly identically to the oracle.
    """
    agent_script = "/home/user/schema_mapper.py"
    oracle_script = "/tests/oracle_schema_mapper.py"

    assert os.path.exists(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script missing: {oracle_script}"

    inputs = generate_fuzz_inputs(500)

    for inp in inputs:
        agent_res = subprocess.run(
            [sys.executable, agent_script, inp],
            capture_output=True,
            text=True
        )
        oracle_res = subprocess.run(
            [sys.executable, oracle_script, inp],
            capture_output=True,
            text=True
        )

        assert oracle_res.returncode == 0, f"Oracle script failed on input {inp}:\n{oracle_res.stderr}"

        if agent_res.returncode != 0:
            pytest.fail(f"Agent script failed on input {inp}.\nStderr: {agent_res.stderr}")

        agent_out = agent_res.stdout.strip()
        oracle_out = oracle_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input: {inp}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent):       {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
