#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/pipeline_audit
cat << 'PY_EOF' > /tmp/pipeline_audit/sitecustomize.py
import json
import os

LOG = os.environ.get("PIPELINE_AUDIT_LOG")

def emit(event):
    if not LOG:
        return
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(event, default=str) + "\n")

try:
    import mongomock.collection
    _original_aggregate = mongomock.collection.Collection.aggregate

    def audited_aggregate(self, pipeline, *args, **kwargs):
        result = _original_aggregate(self, pipeline, *args, **kwargs)
        documents = list(result)
        emit({"event": "aggregate", "pipeline": pipeline, "results": documents})
        return iter(documents)

    mongomock.collection.Collection.aggregate = audited_aggregate
except Exception as exc:
    emit({"event": "instrumentation_error", "component": "mongomock", "error": repr(exc)})

try:
    import networkx as nx
    from networkx.algorithms.link_analysis import pagerank_alg

    _original_pagerank = pagerank_alg.pagerank

    def audited_pagerank(G, *args, **kwargs):
        alpha = kwargs.get("alpha", args[0] if len(args) > 0 else 0.85)
        weight = kwargs.get("weight", args[5] if len(args) > 5 else "weight")
        emit({
            "event": "pagerank",
            "directed": bool(G.is_directed()),
            "nodes": list(G.nodes()),
            "edges": [[u, v, dict(data)] for u, v, data in G.edges(data=True)],
            "alpha": alpha,
            "weight": weight,
        })
        return _original_pagerank(G, *args, **kwargs)

    pagerank_alg.pagerank = audited_pagerank
    nx.pagerank = audited_pagerank
except Exception as exc:
    emit({"event": "instrumentation_error", "component": "networkx", "error": repr(exc)})
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
from pathlib import Path
import subprocess
import sys

INPUT_FILE = Path("/home/user/raw_citations.jsonl")
OUTPUT_FILE = Path("/home/user/pagerank.json")
AUDIT_DIR = Path("/tmp/pipeline_audit")


def compute_pagerank(edges, alpha=0.85, max_iter=100, tol=1e-6):
    """Computes PageRank using the standard iteration used by the original verifier."""
    nodes = set()
    for u, v, w in edges:
        nodes.add(u)
        nodes.add(v)

    N = len(nodes)
    if N == 0:
        return {}

    out_weight = {n: 0.0 for n in nodes}
    for u, v, w in edges:
        out_weight[u] += w

    pr = {n: 1.0 / N for n in nodes}
    for _ in range(max_iter):
        prev_pr = pr.copy()
        dangling_sum = sum(prev_pr[n] for n in nodes if out_weight[n] == 0)

        for n in nodes:
            pr[n] = (1.0 - alpha) / N + alpha * dangling_sum / N

        for u, v, w in edges:
            pr[v] += alpha * prev_pr[u] * w / out_weight[u]

        err = sum(abs(pr[n] - prev_pr[n]) for n in nodes)
        if err < N * tol:
            break

    return pr


def expected_from_input():
    papers = {}
    with INPUT_FILE.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            pid = record["paper_id"]
            if pid not in papers or record["timestamp"] > papers[pid]["timestamp"]:
                papers[pid] = record

    valid_papers = [p for p in papers.values() if not p.get("is_deleted", False)]
    edge_weights = {}
    for p in valid_papers:
        key = (p["author"], p["cited_author"])
        edge_weights[key] = edge_weights.get(key, 0) + 1
    return edge_weights


def read_events(path):
    events = []
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                events.append(json.loads(line))
    return events


def valid_group_pipeline(pipeline):
    for stage in pipeline:
        group = stage.get("$group") if isinstance(stage, dict) else None
        if not isinstance(group, dict):
            continue
        group_id = group.get("_id")
        weight = group.get("weight")
        if (isinstance(group_id, dict)
                and set(group_id.values()) == {"$author", "$cited_author"}
                and isinstance(weight, dict)
                and weight.get("$sum") == 1):
            return True
    return False


def audit_matches(events, expected_edges):
    expected_serialized = {
        (u, v): weight for (u, v), weight in expected_edges.items()
    }

    aggregate_ok = False
    for event in events:
        if event.get("event") != "aggregate" or not valid_group_pipeline(event.get("pipeline", [])):
            continue
        observed = {}
        valid = True
        for document in event.get("results", []):
            group_id = document.get("_id")
            if not isinstance(group_id, dict) or "weight" not in document:
                valid = False
                break
            values = set(group_id.values())
            if len(values) != 2:
                valid = False
                break
            author = next((group_id[k] for k in group_id if "cited" not in k.lower()), None)
            cited = next((group_id[k] for k in group_id if "cited" in k.lower()), None)
            if author is None or cited is None:
                valid = False
                break
            observed[(author, cited)] = document["weight"]
        if valid and observed == expected_serialized:
            aggregate_ok = True
            break

    graph_ok = False
    for event in events:
        if event.get("event") != "pagerank":
            continue
        graph_edges = {}
        for edge in event.get("edges", []):
            if len(edge) != 3 or not isinstance(edge[2], dict):
                continue
            graph_edges[(edge[0], edge[1])] = edge[2].get("weight")
        if (event.get("directed") is True
                and math.isclose(float(event.get("alpha")), 0.85, abs_tol=0.0)
                and event.get("weight") == "weight"
                and graph_edges == expected_serialized):
            graph_ok = True
            break

    return aggregate_ok and graph_ok


def execute_submitted_script(expected_edges):
    candidates = sorted(
        p for p in Path("/home/user").rglob("*.py")
        if p.is_file() and "__pycache__" not in p.parts
    )
    assert candidates, "No Python script was created under /home/user."

    original_input = INPUT_FILE.read_bytes()
    failures = []
    for index, script in enumerate(candidates):
        INPUT_FILE.write_bytes(original_input)
        OUTPUT_FILE.unlink(missing_ok=True)
        audit_log = Path(f"/tmp/pipeline_audit_{index}.jsonl")
        audit_log.unlink(missing_ok=True)

        env = os.environ.copy()
        env["PIPELINE_AUDIT_LOG"] = str(audit_log)
        env["PYTHONPATH"] = str(AUDIT_DIR) + os.pathsep + env.get("PYTHONPATH", "")
        result = subprocess.run(
            [sys.executable, str(script)],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        events = read_events(audit_log)
        if result.returncode == 0 and OUTPUT_FILE.exists() and audit_matches(events, expected_edges):
            INPUT_FILE.write_bytes(original_input)
            return
        failures.append(f"{script}: exit={result.returncode}, output={OUTPUT_FILE.exists()}")

    INPUT_FILE.write_bytes(original_input)
    assert False, "No submitted Python script successfully ran the required mongomock aggregation and NetworkX DiGraph/PageRank pipeline. " + "; ".join(failures)


def test_pagerank_results():
    edge_weights = expected_from_input()
    execute_submitted_script(edge_weights)

    assert OUTPUT_FILE.exists(), f"Output file {OUTPUT_FILE} does not exist. Did the script run and save the output?"

    edges = [(u, v, w) for (u, v), w in edge_weights.items()]
    expected_pr = compute_pagerank(edges)

    with OUTPUT_FILE.open("r", encoding="utf-8") as f:
        try:
            actual_pr = json.load(f)
        except json.JSONDecodeError:
            assert False, f"Output file {OUTPUT_FILE} is not valid JSON."

    assert isinstance(actual_pr, dict), f"Expected JSON object (dict) in {OUTPUT_FILE}, got {type(actual_pr)}"

    missing_nodes = set(expected_pr.keys()) - set(actual_pr.keys())
    extra_nodes = set(actual_pr.keys()) - set(expected_pr.keys())
    assert not missing_nodes, f"Missing authors in PageRank output: {missing_nodes}"
    assert not extra_nodes, f"Unexpected authors in PageRank output: {extra_nodes}"

    for node, expected_score in expected_pr.items():
        actual_score = actual_pr[node]
        assert isinstance(actual_score, (int, float)), f"Score for {node} is not a number: {actual_score}"
        assert math.isclose(actual_score, expected_score, abs_tol=1e-4), \
            f"Mismatch for {node}: expected {expected_score:.5f}, got {actual_score:.5f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
