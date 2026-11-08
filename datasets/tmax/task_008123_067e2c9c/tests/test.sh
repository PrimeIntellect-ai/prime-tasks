#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import re
import secrets
import subprocess

import pytest

BASE_DIR = "/home/user/waf_test_env"
WAF_ANALYZER = os.path.join(BASE_DIR, "waf_analyzer")
RULES_GRAPH = os.path.join(BASE_DIR, "rules_graph.txt")
RESOLVE_RULES = os.path.join(BASE_DIR, "resolve_rules.py")
EXECUTION_PLAN = os.path.join(BASE_DIR, "execution_plan.json")
MAIN_C = os.path.join(BASE_DIR, "src", "main.c")

EXPECTED_COSTS = {
    "init_req": 2,
    "parse_headers": 5,
    "check_sqli": 8,
    "check_xss": 4,
    "rate_limit": 3,
    "forward_req": 1,
}
EXPECTED_DEPS = {
    ("parse_headers", "init_req"),
    ("check_sqli", "parse_headers"),
    ("check_xss", "parse_headers"),
    ("rate_limit", "init_req"),
    ("forward_req", "check_sqli"),
    ("forward_req", "check_xss"),
    ("forward_req", "rate_limit"),
}
EXPECTED_PLAN = [
    "init_req",
    "rate_limit",
    "parse_headers",
    "check_xss",
    "check_sqli",
    "forward_req",
]


def run_checked(command, **kwargs):
    return subprocess.run(
        command,
        cwd=BASE_DIR,
        text=True,
        capture_output=True,
        timeout=15,
        check=True,
        **kwargs,
    )


def parse_graph(text):
    costs = {}
    deps = set()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        rule_match = re.fullmatch(r"Rule:([^\s]+) Cost:(-?\d+)", line)
        dep_match = re.fullmatch(r"Dep:([^\s]+) Requires:([^\s]+)", line)
        if rule_match:
            name, cost = rule_match.groups()
            assert name not in costs, f"Duplicate rule in analyzer output: {name}"
            costs[name] = int(cost)
        elif dep_match:
            deps.add(dep_match.groups())
        elif line:
            pytest.fail(f"Unexpected analyzer output line: {line!r}")
    return costs, deps


def run_resolver(graph_text):
    with open(RULES_GRAPH, "w") as f:
        f.write(graph_text)
    if os.path.exists(EXECUTION_PLAN):
        os.remove(EXECUTION_PLAN)
    run_checked(["python3", RESOLVE_RULES])
    assert os.path.isfile(EXECUTION_PLAN), "resolve_rules.py did not create execution_plan.json"
    with open(EXECUTION_PLAN) as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"execution_plan.json is not valid JSON: {exc}")
    assert isinstance(result, list), "The JSON output must be a list of strings."
    assert all(isinstance(item, str) for item in result), "Every schedule entry must be a string."
    return result


def expected_schedule(costs, dependencies):
    outgoing = {name: [] for name in costs}
    indegree = {name: 0 for name in costs}
    for dependent, required in dependencies:
        outgoing[required].append(dependent)
        indegree[dependent] += 1
    available = [(costs[name], name) for name, degree in indegree.items() if degree == 0]
    heapq.heapify(available)
    result = []
    while available:
        _, name = heapq.heappop(available)
        result.append(name)
        for dependent in outgoing[name]:
            indegree[dependent] -= 1
            if indegree[dependent] == 0:
                heapq.heappush(available, (costs[dependent], dependent))
    assert len(result) == len(costs)
    return result


def graph_text(costs, dependencies):
    rule_lines = [f"Rule:{name} Cost:{cost}" for name, cost in costs.items()]
    dep_lines = [f"Dep:{dependent} Requires:{required}" for dependent, required in dependencies]
    random.shuffle(rule_lines)
    random.shuffle(dep_lines)
    return "\n".join(rule_lines + dep_lines) + "\n"


def test_waf_analyzer_built():
    """Force a fresh Makefile build and verify it produces a real executable binary."""
    for path in (WAF_ANALYZER, os.path.join(BASE_DIR, "src", "main.o")):
        if os.path.exists(path):
            os.remove(path)
    result = run_checked(["make"])
    assert os.path.isfile(WAF_ANALYZER), f"Binary {WAF_ANALYZER} is missing. Did you run make?"
    assert os.access(WAF_ANALYZER, os.X_OK), f"File {WAF_ANALYZER} is not executable."
    with open(WAF_ANALYZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "waf_analyzer must be a compiled ELF binary."
    with open(MAIN_C) as f:
        source = f.read()
    assert re.search(r"^\s*#\s*include\s*[<\"]stdio\.h[>\"]", source, re.MULTILINE), \
        "src/main.c must import stdio.h for printf."


def test_rules_graph_generated():
    """Actually run the analyzer and validate its complete dependency graph."""
    result = run_checked([WAF_ANALYZER])
    with open(RULES_GRAPH, "w") as f:
        f.write(result.stdout)
    assert os.path.isfile(RULES_GRAPH), f"File {RULES_GRAPH} is missing. Did you run the analyzer?"
    with open(RULES_GRAPH) as f:
        content = f.read()
    assert "Rule:init_req" in content, "rules_graph.txt does not contain the expected rule output."
    costs, deps = parse_graph(content)
    assert costs == EXPECTED_COSTS, f"Analyzer emitted incorrect rules or costs: {costs}"
    assert deps == EXPECTED_DEPS, f"Analyzer emitted incorrect dependencies: {deps}"


def test_resolve_rules_script_exists():
    """Test that the Python script resolve_rules.py exists."""
    assert os.path.isfile(RESOLVE_RULES), f"Python script {RESOLVE_RULES} is missing."


def test_execution_plan_json():
    """Run the resolver on analyzer output and check the required schedule."""
    with open(RULES_GRAPH) as f:
        original_graph = f.read()
    data = run_resolver(original_graph)
    assert os.path.isfile(EXECUTION_PLAN), f"JSON file {EXECUTION_PLAN} is missing."
    assert isinstance(data, list), "The JSON output must be a list of strings."
    assert data == EXPECTED_PLAN, f"Execution plan incorrect. Expected {EXPECTED_PLAN}, but got {data}."


def test_resolver_performs_cost_prioritized_topological_sort():
    """Exercise the submitted resolver on unpredictable valid DAGs."""
    with open(RULES_GRAPH) as f:
        original_graph = f.read()
    rng = random.Random(secrets.randbits(128))
    try:
        for case_index in range(5):
            names = [f"r_{secrets.token_hex(5)}" for _ in range(7)]
            costs_list = rng.sample(range(1, 100), len(names))
            costs = dict(zip(names, costs_list))
            topo_seed = names[:]
            rng.shuffle(topo_seed)
            dependencies = set()
            for later in range(1, len(topo_seed)):
                if rng.random() < 0.8:
                    earlier = rng.randrange(later)
                    dependencies.add((topo_seed[later], topo_seed[earlier]))
                for earlier in range(later):
                    if rng.random() < 0.22:
                        dependencies.add((topo_seed[later], topo_seed[earlier]))
            expected = expected_schedule(costs, dependencies)
            actual = run_resolver(graph_text(costs, dependencies))
            assert actual == expected, \
                f"Resolver failed generated DAG case {case_index}: expected {expected}, got {actual}"
    finally:
        # Leave the requested graph and plan in their final, canonical state.
        final = run_resolver(original_graph)
        assert final == EXPECTED_PLAN
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
