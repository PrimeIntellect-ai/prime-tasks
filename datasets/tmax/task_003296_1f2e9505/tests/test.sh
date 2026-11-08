#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the services are available. Initialize them if the agent did not already do so.
service postgresql start >/dev/null 2>&1 || true
redis-server --daemonize yes >/dev/null 2>&1 || true
if ! PGPASSWORD=audit123 psql -h localhost -U auditor -d compliance -c '\q' >/dev/null 2>&1; then
    /app/start_services.sh >/dev/null 2>&1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import psycopg2
import redis

AGENT_BIN = "/home/user/audit"
AGENT_SRC = "/home/user/audit.go"


def test_agent_binary_exists_and_executable():
    assert os.path.isfile(AGENT_SRC), f"Go source {AGENT_SRC} does not exist."
    assert os.path.isfile(AGENT_BIN), f"Agent binary {AGENT_BIN} does not exist. Did you compile your Go code?"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary {AGENT_BIN} is not executable."
    with open(AGENT_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Agent executable is not an ELF binary."
    go_info = subprocess.run(["go", "version", "-m", AGENT_BIN], capture_output=True, text=True)
    assert go_info.returncode == 0, "Agent executable does not contain Go build information."


def run_agent(source_node, target_node, expected):
    proc = subprocess.run(
        [AGENT_BIN, source_node, target_node],
        capture_output=True,
        text=True,
        timeout=8,
    )
    assert proc.returncode == 0, (
        f"Agent failed (exit code {proc.returncode}) on {source_node} {target_node}:\n{proc.stderr}"
    )
    lines = proc.stdout.splitlines()
    assert len(lines) == 1, f"Expected exactly one stdout line, got: {proc.stdout!r}"
    expected_stdout = json.dumps(expected, separators=(",", ":"), ensure_ascii=False)
    assert lines[0] == expected_stdout, (
        f"Mismatch on inputs: source={source_node}, target={target_node}\n"
        f"Expected: {expected_stdout}\nGot:      {lines[0]}"
    )
    assert json.loads(lines[0]) == expected


def test_dynamic_redis_and_graph_cases():
    p = "audit_" + secrets.token_hex(12)
    n = lambda suffix: p + "_" + suffix

    lex_source, lex_a, lex_b, lex_mid, lex_target = map(n, ["lex_s", "a", "b", "mid", "lex_t"])
    chain_source, chain_1, chain_2, chain_target = map(n, ["chain_s", "chain_1", "chain_2", "chain_t"])
    direct_source, direct_target = map(n, ["direct_s", "direct_t"])
    deny_source, deny_target = map(n, ["override_deny_s", "override_deny_t"])
    allow_source, allow_target = map(n, ["override_allow_s", "override_allow_t"])
    missing_source, missing_target = map(n, ["missing_s", "missing_t"])
    cycle_a, cycle_b = map(n, ["cycle_a", "cycle_b"])
    isolated = n("isolated")

    # Insert in deliberately non-lexicographic order and include cycles and distractions.
    edges = [
        (lex_source, lex_b),
        (lex_source, lex_a),
        (lex_b, lex_mid),
        (lex_a, lex_mid),
        (lex_mid, lex_target),
        (lex_mid, lex_source),
        (chain_source, chain_1),
        (chain_1, chain_2),
        (chain_2, chain_target),
        (direct_source, direct_target),
        (deny_source, deny_target),
        (cycle_a, cycle_b),
        (cycle_b, cycle_a),
    ]

    conn = psycopg2.connect(
        dbname="compliance", user="auditor", password="audit123", host="localhost"
    )
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("DELETE FROM access_edges")
            cur.executemany(
                "INSERT INTO access_edges (source_id, target_id) VALUES (%s, %s)", edges
            )
    finally:
        conn.close()

    cache = redis.Redis(host="localhost", port=6379, decode_responses=True)
    cache.flushdb()
    cache.set(f"override:{allow_source}:{allow_target}", "ALLOW")
    cache.set(f"override:{deny_source}:{deny_target}", "DENY")

    cases = [
        (allow_source, allow_target, {"status":"ALLOW","path":[allow_source,allow_target],"reason":"redis_override"}),
        (deny_source, deny_target, {"status":"DENY","path":[],"reason":"redis_override"}),
        (lex_source, lex_target, {"status":"ALLOW","path":[lex_source,lex_a,lex_mid,lex_target],"reason":"graph_path"}),
        (chain_source, chain_target, {"status":"ALLOW","path":[chain_source,chain_1,chain_2,chain_target],"reason":"graph_path"}),
        (direct_source, direct_target, {"status":"ALLOW","path":[direct_source,direct_target],"reason":"graph_path"}),
        (missing_source, missing_target, {"status":"DENY","path":[],"reason":"no_path"}),
        (cycle_a, missing_target, {"status":"DENY","path":[],"reason":"no_path"}),
        (isolated, isolated, {"status":"ALLOW","path":[isolated],"reason":"graph_path"}),
    ]

    for source_node, target_node, expected in cases:
        run_agent(source_node, target_node, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
