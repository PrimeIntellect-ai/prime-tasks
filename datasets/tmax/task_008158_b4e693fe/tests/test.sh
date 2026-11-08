#!/bin/bash
set -e
mkdir -p /logs/verifier

if (
    set -e

    script_path="/home/user/aggregate_research.py"
    csv_path="/home/user/author_metrics.csv"
    data_dir="/home/user/data"
    work_dir="$(mktemp -d)"

    test -f "$script_path"

    cp "$data_dir/publications.ttl" "$work_dir/publications.ttl"
    cp "$data_dir/experiments.jsonl" "$work_dir/experiments.jsonl"

    restore_files() {
        cp "$work_dir/publications.ttl" "$data_dir/publications.ttl"
        cp "$work_dir/experiments.jsonl" "$data_dir/experiments.jsonl"
        if [ -f "$work_dir/final_author_metrics.csv" ]; then
            cp "$work_dir/final_author_metrics.csv" "$csv_path"
        fi
        rm -rf "$work_dir"
    }
    trap restore_files EXIT

    mkdir -p "$work_dir/hook"
    cat << 'PY_EOF' > "$work_dir/hook/sitecustomize.py"
import os
import rdflib

_original_query = rdflib.Graph.query

def _tracked_query(self, query_object, *args, **kwargs):
    text = str(query_object).lower()
    required = ("select", "where", "machinelearning", "hastopic", "hasauthor", "name")
    if all(token in text for token in required):
        marker = os.environ.get("QUERY_MARKER")
        if marker:
            with open(marker, "a", encoding="utf-8") as f:
                f.write("VALID_SPARQL_QUERY\n")
    return _original_query(self, query_object, *args, **kwargs)

rdflib.Graph.query = _tracked_query
PY_EOF

    run_submission() {
        rm -f "$csv_path" "$work_dir/query.marker"
        QUERY_MARKER="$work_dir/query.marker" \
        PYTHONPATH="$work_dir/hook${PYTHONPATH:+:$PYTHONPATH}" \
        python3 "$script_path"
        test -f "$csv_path"
        test -f "$work_dir/query.marker"
        grep -q '^VALID_SPARQL_QUERY$' "$work_dir/query.marker"
    }

    # Execute the submitted artifact against the original datasets.
    run_submission

    cat << 'TEST_EOF' > "$work_dir/test_final_state.py"
# test_final_state.py

import os
import csv
import pytest

def test_author_metrics_csv_exists_and_content():
    csv_path = "/home/user/author_metrics.csv"
    assert os.path.exists(csv_path), f"The file {csv_path} was not created."

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The CSV file is empty."

    expected_header = ["Author", "Avg_Accuracy", "Avg_F1"]
    assert rows[0] == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {rows[0]}"

    # The expected data derived from the cross-query aggregation of publications.ttl and experiments.jsonl
    # Pub1 (ML): Alice Smith, Bob Jones. Acc: 0.955, F1: 0.925
    # Pub2 (ML): Alice Smith, Charlie Brown. Acc: 0.885, F1: 0.855
    # Pub3 (Databases): Ignored
    # Pub4 (ML): Charlie Brown. Acc: 0.910, F1: 0.900
    #
    # Author Aggregation:
    # Alice Smith: (0.955 + 0.885)/2 = 0.9200, (0.925 + 0.855)/2 = 0.8900
    # Bob Jones: 0.9550, 0.9250
    # Charlie Brown: (0.885 + 0.910)/2 = 0.8975, (0.855 + 0.900)/2 = 0.8775

    expected_data = [
        ["Alice Smith", "0.9200", "0.8900"],
        ["Bob Jones", "0.9550", "0.9250"],
        ["Charlie Brown", "0.8975", "0.8775"]
    ]

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(data_rows)}."

    for i, (expected, actual) in enumerate(zip(expected_data, data_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

    python3 -m pytest "$work_dir/test_final_state.py" -x --tb=short
    cp "$csv_path" "$work_dir/final_author_metrics.csv"

    # Replace both inputs with an alternate fixture so hardcoded original rows fail.
    cat << 'TTL_EOF' > "$data_dir/publications.ttl"
@prefix ex: <http://example.org/> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

ex:StudyA a ex:Publication ;
    ex:hasTopic ex:topic/MachineLearning ;
    ex:hasAuthor ex:AuthorAmy, ex:AuthorZed .

ex:StudyB a ex:Publication ;
    ex:hasTopic ex:topic/MachineLearning ;
    ex:hasAuthor ex:AuthorAmy .

ex:StudyC a ex:Publication ;
    ex:hasTopic ex:topic/Databases ;
    ex:hasAuthor ex:AuthorAmy .

ex:StudyD a ex:Publication ;
    ex:hasTopic ex:topic/MachineLearning ;
    ex:hasAuthor ex:AuthorZed .

ex:AuthorAmy foaf:name "Amy Alpha" .
ex:AuthorZed foaf:name "Zed Zebra" .
TTL_EOF

    cat << 'JSON_EOF' > "$data_dir/experiments.jsonl"
{"pub_id":"StudyA","experiment_id":"a1","metrics":{"accuracy":0.700,"f1_score":0.600}}
{"pub_id":"StudyA","experiment_id":"a2","metrics":{"accuracy":0.800,"f1_score":0.700}}
{"pub_id":"StudyB","experiment_id":"b1","metrics":{"accuracy":0.910,"f1_score":0.810}}
{"pub_id":"StudyB","experiment_id":"b2","metrics":{"accuracy":0.930,"f1_score":0.830}}
{"pub_id":"StudyC","experiment_id":"c1","metrics":{"accuracy":0.999,"f1_score":0.999}}
{"pub_id":"StudyD","experiment_id":"d1","metrics":{"accuracy":0.510,"f1_score":0.410}}
JSON_EOF

    run_submission

    cat << 'DYNAMIC_EOF' > "$work_dir/test_dynamic_state.py"
import csv
import json
from collections import defaultdict
from rdflib import Graph, Namespace
from rdflib.namespace import FOAF


def derive_expected():
    graph = Graph()
    graph.parse("/home/user/data/publications.ttl", format="turtle")
    ex = Namespace("http://example.org/")
    ml_topic = ex["topic/MachineLearning"]

    publication_authors = {}
    for publication in graph.subjects(ex.hasTopic, ml_topic):
        pub_id = str(publication).rsplit("/", 1)[-1]
        names = []
        for author in graph.objects(publication, ex.hasAuthor):
            names.extend(str(name) for name in graph.objects(author, FOAF.name))
        publication_authors[pub_id] = names

    metrics = defaultdict(lambda: [[], []])
    with open("/home/user/data/experiments.jsonl", "r", encoding="utf-8") as f:
        for line in f:
            document = json.loads(line)
            metrics[document["pub_id"]][0].append(float(document["metrics"]["accuracy"]))
            metrics[document["pub_id"]][1].append(float(document["metrics"]["f1_score"]))

    author_values = defaultdict(lambda: [[], []])
    for pub_id, authors in publication_authors.items():
        accuracy_values, f1_values = metrics[pub_id]
        pub_accuracy = sum(accuracy_values) / len(accuracy_values)
        pub_f1 = sum(f1_values) / len(f1_values)
        for author in authors:
            author_values[author][0].append(pub_accuracy)
            author_values[author][1].append(pub_f1)

    expected = []
    for author in sorted(author_values):
        accuracies, f1_scores = author_values[author]
        expected.append([
            author,
            f"{sum(accuracies) / len(accuracies):.4f}",
            f"{sum(f1_scores) / len(f1_scores):.4f}",
        ])
    return [["Author", "Avg_Accuracy", "Avg_F1"], *expected]


def test_alternate_inputs_are_aggregated_and_formatted():
    with open("/home/user/author_metrics.csv", "r", encoding="utf-8", newline="") as f:
        actual = list(csv.reader(f))
    assert actual == derive_expected()
DYNAMIC_EOF

    python3 -m pytest "$work_dir/test_dynamic_state.py" -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
