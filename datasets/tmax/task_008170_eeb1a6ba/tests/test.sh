#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess


def test_script_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_run_directory_exists():
    run_dir = "/home/user/runs/test_run"
    assert os.path.isdir(run_dir), f"Run directory {run_dir} does not exist. Did you run the script with 'test_run'?"


def test_invalid_log_content():
    log_path = "/home/user/runs/test_run/invalid.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["ds4_invalid.json", "ds6_invalid.json"]
    assert lines == expected_lines, f"Expected {expected_lines} in invalid.log, but got {lines}."


def test_metrics_txt_content():
    metrics_path = "/home/user/runs/test_run/metrics.txt"
    assert os.path.isfile(metrics_path), f"File {metrics_path} does not exist."

    with open(metrics_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Total: 6",
        "Valid: 4",
        "Invalid: 2"
    ]
    assert lines == expected_lines, f"Expected {expected_lines} in metrics.txt, but got {lines}."


def test_recommendations_tsv_content():
    tsv_path = "/home/user/runs/test_run/recommendations.tsv"
    assert os.path.isfile(tsv_path), f"File {tsv_path} does not exist."

    with open(tsv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "d1\td2\t0.50",
        "d2\td1\t0.50",
        "d3\td5\t0.25",
        "d5\td3\t0.25"
    ]
    assert lines == expected_lines, f"Expected {expected_lines} in recommendations.tsv, but got {lines}."


def test_exactly_one_argument_is_required():
    script = "/home/user/run_pipeline.sh"
    run_name = "argcheck_" + secrets.token_hex(6)
    run_dir = os.path.join("/home/user/runs", run_name)
    try:
        no_args = subprocess.run([script], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        assert no_args.returncode != 0, "The script must reject invocation with no run name."

        two_args = subprocess.run(
            [script, run_name, "unexpected_second_argument"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert two_args.returncode != 0, "The script must reject invocation with more than one argument."
    finally:
        shutil.rmtree(run_dir, ignore_errors=True)


def test_pipeline_executes_on_changed_dataset_collection():
    script = "/home/user/run_pipeline.sh"
    datasets = "/home/user/datasets"
    backup = "/home/user/datasets.verifier_backup_" + secrets.token_hex(8)
    run_name = "dynamic_" + secrets.token_hex(8)
    run_dir = os.path.join("/home/user/runs", run_name)

    token = lambda prefix: prefix + "_" + secrets.token_hex(5)
    tags = [token("tag") for _ in range(4)]
    ids = [token("id") for _ in range(6)]

    valid_records = [
        {"id": ids[0], "name": "first",  "tags": [tags[0], tags[1], tags[0]]},
        {"id": ids[1], "name": "second", "tags": [tags[0]]},
        {"id": ids[2], "name": "third",  "tags": [tags[1]]},
        {"id": ids[3], "name": "fourth", "tags": [tags[2], tags[3]]},
        {"id": ids[4], "name": "fifth",  "tags": [tags[2]]},
        {"id": ids[5], "name": "sixth",  "tags": [tags[3]]},
    ]

    valid_files = [(token("valid") + ".json", record) for record in valid_records]
    invalid_files = {
        token("missing_tags") + ".json": {"id": token("badid"), "name": "missing"},
        token("numeric_id") + ".json": {"id": 17, "name": "numeric", "tags": [tags[0]]},
        token("bad_name") + ".json": {"id": token("badid"), "name": ["not", "string"], "tags": [tags[0]]},
        token("mixed_tags") + ".json": {"id": token("badid"), "name": "mixed", "tags": [tags[0], 3]},
        token("empty_tags") + ".json": {"id": token("badid"), "name": "empty", "tags": []},
    }
    malformed_name = token("malformed") + ".json"

    def expected_recommendations(records):
        result = []
        for record in records:
            source_tags = set(record["tags"])
            candidates = []
            for other in records:
                if other is record:
                    continue
                other_tags = set(other["tags"])
                score = len(source_tags & other_tags) / len(source_tags | other_tags)
                candidates.append((score, other["id"]))
            best_score = max(score for score, _ in candidates)
            best_id = min(other_id for score, other_id in candidates if score == best_score)
            result.append(f'{record["id"]}\t{best_id}\t{best_score:.2f}')
        return sorted(result, key=lambda line: line.split("\t", 1)[0])

    os.rename(datasets, backup)
    os.mkdir(datasets)
    try:
        for filename, record in valid_files:
            with open(os.path.join(datasets, filename), "w") as f:
                json.dump(record, f)
        for filename, record in invalid_files.items():
            with open(os.path.join(datasets, filename), "w") as f:
                json.dump(record, f)
        with open(os.path.join(datasets, malformed_name), "w") as f:
            f.write('{"id": "broken", "name": ')

        completed = subprocess.run(
            [script, run_name],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, (
            f"Pipeline failed on changed datasets with exit code {completed.returncode}. "
            f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
        )
        assert os.path.isdir(run_dir), "The requested dynamic run directory was not created."

        invalid_path = os.path.join(run_dir, "invalid.log")
        metrics_path = os.path.join(run_dir, "metrics.txt")
        recommendations_path = os.path.join(run_dir, "recommendations.tsv")
        assert os.path.isfile(invalid_path), "Dynamic run did not create invalid.log."
        assert os.path.isfile(metrics_path), "Dynamic run did not create metrics.txt."
        assert os.path.isfile(recommendations_path), "Dynamic run did not create recommendations.tsv."

        expected_invalid = sorted(list(invalid_files) + [malformed_name])
        with open(invalid_path) as f:
            actual_invalid = f.read().splitlines()
        assert actual_invalid == expected_invalid

        expected_metrics = [
            f"Total: {len(valid_records) + len(expected_invalid)}",
            f"Valid: {len(valid_records)}",
            f"Invalid: {len(expected_invalid)}",
        ]
        with open(metrics_path) as f:
            actual_metrics = f.read().splitlines()
        assert actual_metrics == expected_metrics

        with open(recommendations_path) as f:
            actual_recommendations = f.read().splitlines()
        assert actual_recommendations == expected_recommendations(valid_records)
    finally:
        shutil.rmtree(datasets, ignore_errors=True)
        os.rename(backup, datasets)
        shutil.rmtree(run_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
