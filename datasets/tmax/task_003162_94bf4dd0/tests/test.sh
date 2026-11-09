#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import textwrap
from collections import Counter

import pytest


def test_files_exist():
    expected_files = [
        "/home/user/optimizer.c",
        "/home/user/verify_connectivity.exp",
        "/home/user/apply.sh",
    ]
    for path in expected_files:
        assert os.path.exists(path), f"Missing required file: {path}"


def test_apply_script_runs_and_generates_outputs():
    # Run the agent's pipeline
    apply_script = "/home/user/apply.sh"
    assert os.access(apply_script, os.X_OK), f"{apply_script} is not executable"

    result = subprocess.run(["bash", apply_script], capture_output=True, text=True)
    assert result.returncode == 0, f"apply.sh failed with return code {result.returncode}\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"

    # Check generated files
    assert os.path.exists("/home/user/optimizer"), "Optimizer binary was not compiled."
    assert os.path.exists("/home/user/optimized_policies.txt"), "Optimized policies file was not generated."


def read_rules(path):
    rules = []
    with open(path, "r") as f:
        for lineno, line in enumerate(f, 1):
            if not line.strip():
                continue
            fields = line.split()
            assert len(fields) == 4, f"Malformed rule at {path}:{lineno}: {line.rstrip()}"
            rule_id, src, dst, action = fields
            assert rule_id.isdigit(), f"Invalid rule ID at {path}:{lineno}"
            assert action in ("ALLOW", "DENY"), f"Invalid action at {path}:{lineno}"
            rules.append(tuple(fields))
    return rules


def test_optimized_policies_metric_and_semantics():
    stats_file = "/home/user/traffic_stats.csv"
    base_policies = "/home/user/base_policies.txt"
    optimized_policies = "/home/user/optimized_policies.txt"
    oracle_bin = "/app/policy_oracle"

    assert os.path.exists(stats_file), f"Missing {stats_file}"
    assert os.path.exists(base_policies), f"Missing {base_policies}"
    assert os.path.exists(optimized_policies), f"Missing {optimized_policies}"
    assert os.path.exists(oracle_bin), f"Missing {oracle_bin}"

    # Optimization must only reorder the supplied policy rules. It may not
    # remove rules, duplicate rules, or introduce broader replacement rules.
    base_rules = read_rules(base_policies)
    optimized_rules = read_rules(optimized_policies)
    assert len(base_rules) == 200, f"Expected 200 base rules, found {len(base_rules)}"
    assert len(optimized_rules) == len(base_rules), "Optimized policy has a different rule count."
    assert Counter(optimized_rules) == Counter(base_rules), \
        "optimized_policies.txt is not a permutation of the base policy rules."

    queries = []
    freqs = []
    with open(stats_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            src, dst, freq = line.split(',')
            queries.append(f"query {src} {dst}\n")
            freqs.append(int(freq))

    query_str = "".join(queries)

    # Run baseline to get expected semantics
    p_base = subprocess.Popen([oracle_bin, base_policies],
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    out_base, _ = p_base.communicate(query_str)
    base_results = out_base.strip().split('\n')

    # Run optimized
    p_opt = subprocess.Popen([oracle_bin, optimized_policies],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    out_opt, _ = p_opt.communicate(query_str)
    opt_results = out_opt.strip().split('\n')

    assert len(base_results) == len(opt_results) == len(freqs), "Oracle output length mismatch."

    total_weighted_latency = 0
    total_frequency = 0

    for i in range(len(freqs)):
        base_action = base_results[i].split()[0]
        opt_action = opt_results[i].split()[0]

        assert base_action == opt_action, f"Semantics changed for query {queries[i].strip()}! Expected {base_action}, got {opt_action}"

        latency_str = opt_results[i].split()[1]
        assert latency_str.endswith("ms"), f"Unexpected latency format: {latency_str}"
        latency = int(latency_str.replace('ms', ''))

        total_weighted_latency += latency * freqs[i]
        total_frequency += freqs[i]

    assert total_frequency > 0, "No traffic frequencies found."

    avg_latency = total_weighted_latency / total_frequency
    threshold = 12.5

    assert avg_latency <= threshold, f"FAILURE: Average latency {avg_latency:.2f} exceeds the threshold > {threshold}"


FAKE_ORACLE = r'''#!/usr/bin/env python3
import ipaddress
import os
import sys

policy = sys.argv[1]
rules = []
with open(policy) as f:
    for line in f:
        fields = line.split()
        if len(fields) == 4:
            _, src, dst, action = fields
            rules.append((ipaddress.ip_network(src, strict=False),
                          ipaddress.ip_network(dst, strict=False), action))

log_path = os.environ["VERIFY_QUERY_LOG"]
mode = os.environ.get("VERIFY_ORACLE_MODE", "normal")
target = os.environ.get("VERIFY_TARGET", "")

for line in sys.stdin:
    fields = line.split()
    if len(fields) != 3 or fields[0] != "query":
        continue
    src, dst = fields[1], fields[2]
    pair = src + "," + dst
    with open(log_path, "a") as log:
        log.write(pair + "\n")

    src_ip = ipaddress.ip_address(src)
    dst_ip = ipaddress.ip_address(dst)
    action = "DENY"
    latency = len(rules)
    for index, (src_net, dst_net, rule_action) in enumerate(rules, 1):
        if src_ip in src_net and dst_ip in dst_net:
            action = rule_action
            latency = index
            break

    if pair == target and mode == "deny":
        action = "DENY"
    if pair == target and mode == "bad_latency":
        print(f"{action} not-a-latency", flush=True)
    else:
        print(f"{action} {latency}ms", flush=True)
'''


def run_expect_with_instrumented_oracle(mode, target):
    oracle = "/app/policy_oracle"
    backup = f"/tmp/policy_oracle.real.{os.getpid()}"
    fd, log_path = tempfile.mkstemp(prefix="expect_queries_", text=True)
    os.close(fd)

    os.replace(oracle, backup)
    try:
        with open(oracle, "w") as f:
            f.write(FAKE_ORACLE)
        os.chmod(oracle, 0o755)

        env = os.environ.copy()
        env["VERIFY_QUERY_LOG"] = log_path
        env["VERIFY_ORACLE_MODE"] = mode
        env["VERIFY_TARGET"] = target
        try:
            result = subprocess.run(
                ["/usr/bin/expect", "/home/user/verify_connectivity.exp"],
                capture_output=True, text=True, env=env, timeout=20
            )
        except subprocess.TimeoutExpired as e:
            pytest.fail(f"verify_connectivity.exp timed out in {mode} probe: {e}")

        with open(log_path) as f:
            queried = [line.strip() for line in f if line.strip()]
        return result, queried
    finally:
        if os.path.exists(oracle):
            os.remove(oracle)
        os.replace(backup, oracle)
        if os.path.exists(log_path):
            os.remove(log_path)


def test_connectivity_expect_script_queries_and_validates_top_five():
    rows = []
    with open("/home/user/traffic_stats.csv") as f:
        for line in f:
            if line.strip():
                src, dst, freq = line.strip().split(',')
                rows.append((int(freq), src, dst))
    rows.sort(key=lambda row: row[0], reverse=True)
    assert len(rows) >= 5, "Fewer than five traffic rows are available."
    top_five = [f"{src},{dst}" for _, src, dst in rows[:5]]

    normal, queried = run_expect_with_instrumented_oracle("normal", "")
    assert normal.returncode == 0, \
        f"verify_connectivity.exp failed on valid ALLOW responses.\nSTDOUT:\n{normal.stdout}\nSTDERR:\n{normal.stderr}"
    for pair in top_five:
        assert pair in queried, f"verify_connectivity.exp did not query top-five pair {pair}"

    denied, denied_queries = run_expect_with_instrumented_oracle("deny", top_five[0])
    assert top_five[0] in denied_queries, "DENY validation probe was not queried."
    assert denied.returncode != 0, \
        "verify_connectivity.exp did not fail when a top-five query returned DENY."

    malformed, malformed_queries = run_expect_with_instrumented_oracle("bad_latency", top_five[1])
    assert top_five[1] in malformed_queries, "Latency validation probe was not queried."
    assert malformed.returncode != 0, \
        "verify_connectivity.exp did not fail when a top-five query returned an invalid latency."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
