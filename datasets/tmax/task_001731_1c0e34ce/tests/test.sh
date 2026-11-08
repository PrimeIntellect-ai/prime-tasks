#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid
from collections import Counter
from decimal import Decimal


def test_part1_keyframe_count():
    count_file = "/home/user/keyframe_count.txt"
    assert os.path.exists(count_file), f"Task 1 failed: {count_file} does not exist"
    with open(count_file, "r") as f:
        content = f.read().strip()

    # Preserve the original assertion and independently derive the answer from
    # the actual video rather than trusting a fixed expected value alone.
    assert content == "14", f"Task 1 failed: Expected keyframe count 14, but got '{content}'"
    assert re.fullmatch(r"[0-9]+", content), "Task 1 failed: count is not an integer"
    probe = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_frames", "-show_entries", "frame=key_frame",
            "-of", "json", "/app/network_simulation.mp4"
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    frames = json.loads(probe.stdout).get("frames", [])
    expected = sum(1 for frame in frames if int(frame.get("key_frame", 0)) == 1)
    assert int(content) == expected, (
        f"Task 1 failed: file reports {content}, but ffprobe found {expected} keyframes"
    )


def test_part2_adversarial_filtering():
    script_path = "/home/user/sanitize_graphs.sh"
    assert os.path.exists(script_path), f"Task 2 failed: {script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"Task 2 failed: {script_path} is not executable"

    clean_corpus_dir = "/app/corpora/clean/"
    evil_corpus_dir = "/app/corpora/evil/"

    with tempfile.TemporaryDirectory() as temp_out_clean, tempfile.TemporaryDirectory() as temp_out_evil:
        subprocess.run([script_path, clean_corpus_dir, temp_out_clean], check=False, timeout=30)
        subprocess.run([script_path, evil_corpus_dir, temp_out_evil], check=False, timeout=30)

        clean_input_files = set(f for f in os.listdir(clean_corpus_dir) if f.endswith('.json'))
        clean_output_files = set(f for f in os.listdir(temp_out_clean) if f.endswith('.json'))
        evil_input_files = set(f for f in os.listdir(evil_corpus_dir) if f.endswith('.json'))
        evil_output_files = set(f for f in os.listdir(temp_out_evil) if f.endswith('.json'))

        clean_modified = []
        for name in clean_input_files:
            if name not in clean_output_files:
                clean_modified.append(name)
            else:
                with open(os.path.join(clean_corpus_dir, name)) as f1, open(os.path.join(temp_out_clean, name)) as f2:
                    if f1.read() != f2.read():
                        clean_modified.append(name)

        evil_bypassed = list(evil_output_files)
        errors = []
        if evil_bypassed:
            errors.append(f"{len(evil_bypassed)} of {len(evil_input_files)} evil bypassed: {', '.join(evil_bypassed)}")
        if clean_modified:
            errors.append(f"{len(clean_modified)} of {len(clean_input_files)} clean modified/rejected: {', '.join(clean_modified)}")
        assert not errors, "Adversarial corpus failure: " + " | ".join(errors)


def test_part2_general_filtering_rules():
    script_path = "/home/user/sanitize_graphs.sh"
    token = uuid.uuid4().hex

    valid_graphs = {
        f"valid_{token}_a.json": {
            "nodes": [
                {"id": f"Node_{token}", "indexed": True, "idx_key": "lookup"},
                {"id": f"peer-{token}", "indexed": False},
            ],
            "edges": [
                {"source": f"Node_{token}", "target": f"peer-{token}", "weight": 0},
                {"source": f"peer-{token}", "target": f"Node_{token}", "weight": 17},
            ],
        },
        f"valid_{token}_b.json": {
            "nodes": [
                {"id": f"A{token}"},
                {"id": f"B_{token}", "indexed": True, "idx_key": "present"},
            ],
            "edges": [{"source": f"A{token}", "target": f"B_{token}", "weight": 2.5}],
        },
    }

    invalid_graphs = {
        f"negative_{token}.json": {
            "nodes": [{"id": f"N{token}"}],
            "edges": [{"source": f"N{token}", "target": f"N{token}", "weight": -0.25}],
        },
        f"bad_id_{token}.json": {
            "nodes": [{"id": f"bad id/{token}"}],
            "edges": [],
        },
        f"missing_key_{token}.json": {
            "nodes": [{"id": f"I{token}", "indexed": True}],
            "edges": [],
        },
    }

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        original_bytes = {}
        for name, graph in {**valid_graphs, **invalid_graphs}.items():
            path = os.path.join(input_dir, name)
            with open(path, "w") as f:
                json.dump(graph, f, indent=2)
                f.write("\n")
            with open(path, "rb") as f:
                original_bytes[name] = f.read()

        malformed_name = f"malformed_{token}.json"
        malformed_path = os.path.join(input_dir, malformed_name)
        with open(malformed_path, "w") as f:
            f.write('{"nodes":[{"id":"broken"}],"edges":[')

        subprocess.run([script_path, input_dir, output_dir], check=False, timeout=30)

        actual = set(name for name in os.listdir(output_dir) if name.endswith(".json"))
        expected = set(valid_graphs)
        assert actual == expected, (
            f"Task 2 failed on generated inputs: expected copied files {sorted(expected)}, "
            f"got {sorted(actual)}"
        )
        for name in expected:
            with open(os.path.join(output_dir, name), "rb") as f:
                assert f.read() == original_bytes[name], f"Task 2 modified clean file {name}"


def _number(value):
    assert not isinstance(value, bool), "boolean is not a numeric edge weight"
    return Decimal(str(value))


def test_part3_convert_script():
    script_path = "/home/user/convert.sh"
    assert os.path.exists(script_path), f"Task 3 failed: {script_path} does not exist"
    assert os.access(script_path, os.X_OK), f"Task 3 failed: {script_path} is not executable"

    suffix = uuid.uuid4().hex[:10]
    node_ids = [f"node_{suffix}_{i}" for i in range(5)]
    edges = [
        {"source": node_ids[0], "target": node_ids[1], "weight": 3},
        {"source": node_ids[0], "target": node_ids[2], "weight": 11},
        {"source": node_ids[2], "target": node_ids[3], "weight": 7},
        {"source": node_ids[3], "target": node_ids[1], "weight": 19},
    ]
    sample_json = {
        "nodes": [{"id": node_id} for node_id in node_ids],
        "edges": edges,
    }

    output_csv = "/home/user/export_relational.csv"
    output_jsonl = "/home/user/export_document.jsonl"
    output_dot = "/home/user/export_graph.dot"

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as tmp:
        json.dump(sample_json, tmp)
        tmp_path = tmp.name

    try:
        for out_file in [output_csv, output_jsonl, output_dot]:
            if os.path.exists(out_file):
                os.remove(out_file)

        subprocess.run([script_path, tmp_path], check=False, timeout=30)

        assert os.path.exists(output_csv), f"Task 3 failed: {output_csv} was not created"
        assert os.path.exists(output_jsonl), f"Task 3 failed: {output_jsonl} was not created"
        assert os.path.exists(output_dot), f"Task 3 failed: {output_dot} was not created"

        # Relational representation: exact header and exact edge multiset.
        with open(output_csv, newline="") as f:
            reader = csv.reader(f)
            rows = list(reader)
        assert rows, "Task 3 failed: CSV is empty"
        assert rows[0] == ["source", "target", "weight"], (
            f"Task 3 failed: CSV header must be source,target,weight, got {rows[0]}"
        )
        assert all(len(row) == 3 for row in rows[1:]), "Task 3 failed: malformed CSV row"
        actual_csv = Counter((row[0], row[1], _number(row[2])) for row in rows[1:])
        expected_edges = Counter((e["source"], e["target"], _number(e["weight"])) for e in edges)
        assert actual_csv == expected_edges, "Task 3 failed: CSV edges do not match the input graph"

        # Document representation: one document per node and the exact outgoing edges.
        documents = []
        with open(output_jsonl) as f:
            for line_number, line in enumerate(f, 1):
                if not line.strip():
                    continue
                try:
                    document = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise AssertionError(f"Task 3 failed: invalid JSONL on line {line_number}: {exc}")
                assert isinstance(document, dict), "Task 3 failed: each JSONL line must be an object"
                documents.append(document)

        assert len(documents) == len(node_ids), "Task 3 failed: JSONL must contain one document per node"
        by_id = {}
        for document in documents:
            assert isinstance(document.get("id"), str), "Task 3 failed: JSONL node document lacks an id"
            node_id = document["id"]
            assert node_id not in by_id, f"Task 3 failed: duplicate JSONL node {node_id}"
            by_id[node_id] = document
        assert set(by_id) == set(node_ids), "Task 3 failed: JSONL node IDs do not match the input"

        for node_id in node_ids:
            document = by_id[node_id]
            outgoing = document.get("outgoing_edges", document.get("edges"))
            assert isinstance(outgoing, list), (
                f"Task 3 failed: document for {node_id} lacks an outgoing edge array"
            )
            actual_outgoing = Counter()
            for edge in outgoing:
                assert isinstance(edge, dict) and "target" in edge and "weight" in edge, (
                    f"Task 3 failed: malformed outgoing edge for {node_id}"
                )
                actual_outgoing[(edge["target"], _number(edge["weight"]))] += 1
            expected_outgoing = Counter(
                (edge["target"], _number(edge["weight"]))
                for edge in edges if edge["source"] == node_id
            )
            assert actual_outgoing == expected_outgoing, (
                f"Task 3 failed: outgoing edges for {node_id} do not match the input"
            )

        # DOT representation: validate syntax with Graphviz when available, then
        # ensure every node and weighted directed edge from the input is present.
        with open(output_dot) as f:
            dot_text = f.read()
        assert dot_text.strip(), "Task 3 failed: DOT output is empty"
        assert re.search(r"\bdigraph\b[^\{]*\{", dot_text, re.IGNORECASE | re.DOTALL), (
            "Task 3 failed: DOT output is not a directed graph"
        )
        assert dot_text.rstrip().endswith("}"), "Task 3 failed: DOT graph is not closed"

        dot_binary = shutil.which("dot")
        if dot_binary:
            parsed = subprocess.run(
                [dot_binary, "-Tdot", output_dot, "-o", os.devnull],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert parsed.returncode == 0, f"Task 3 failed: invalid DOT syntax: {parsed.stderr}"

        for node_id in node_ids:
            token_pattern = rf'(?<![A-Za-z0-9_])(?:"{re.escape(node_id)}"|{re.escape(node_id)})(?![A-Za-z0-9_])'
            assert re.search(token_pattern, dot_text), f"Task 3 failed: DOT omits node {node_id}"

        found_edge_statements = 0
        for edge in edges:
            source = re.escape(edge["source"])
            target = re.escape(edge["target"])
            pattern = rf'(?:"{source}"|{source})\s*->\s*(?:"{target}"|{target})\s*(\[[^\]]*\])?'
            match = re.search(pattern, dot_text, re.DOTALL)
            assert match, f"Task 3 failed: DOT omits edge {edge['source']} -> {edge['target']}"
            found_edge_statements += 1
            attrs = match.group(1) or ""
            weight = re.escape(str(edge["weight"]))
            assert re.search(rf'\b(?:label|weight)\s*=\s*"?{weight}"?', attrs), (
                f"Task 3 failed: DOT edge {edge['source']} -> {edge['target']} omits its weight"
            )
        assert found_edge_statements == len(edges)
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
