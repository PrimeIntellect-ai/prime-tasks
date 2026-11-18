#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/process_configs.py"
CLEAN_CORPUS_DIR = "/app/data/corpus/clean"
EVIL_CORPUS_DIR = "/app/data/corpus/evil"
EVAL_CLEAN_DIR = "/tmp/eval_clean"
EVAL_EVIL_DIR = "/tmp/eval_evil"
EXPECTED_LOAD_FACTOR = 0.85


def run_script(input_dir, output_dir):
    proc = subprocess.run(
        ["python3", SCRIPT_PATH, "--input-dir", input_dir, "--output-dir", output_dir],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Script failed. stdout: {proc.stdout}\nstderr: {proc.stderr}"


def is_corrupted(records):
    for i in range(len(records)):
        for j in range(i + 1, len(records)):
            if abs(records[i]["timestamp"] - records[j]["timestamp"]) <= 2.0:
                distance = math.sqrt(sum(
                    (records[i]["metrics"][k] - records[j]["metrics"][k]) ** 2
                    for k in range(4)
                ))
                if distance < 0.05:
                    return True
    return False


def expected_output(records):
    result = []
    for record in records:
        copied = dict(record)
        if copied["load_factor"] is None:
            copied["load_factor"] = EXPECTED_LOAD_FACTOR
        result.append(copied)
    return result


@pytest.fixture(scope="session", autouse=True)
def run_agent_script():
    assert os.path.exists(SCRIPT_PATH), f"Agent script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Agent script is not a regular file: {SCRIPT_PATH}"

    for directory in [EVAL_CLEAN_DIR, EVAL_EVIL_DIR]:
        if os.path.exists(directory):
            shutil.rmtree(directory)
        os.makedirs(directory)

    run_script(CLEAN_CORPUS_DIR, EVAL_CLEAN_DIR)
    run_script(EVIL_CORPUS_DIR, EVAL_EVIL_DIR)


def test_evil_corpus_rejected():
    evil_input_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.json"))
    evil_output_files = glob.glob(os.path.join(EVAL_EVIL_DIR, "*.json"))
    bypassed_files = [os.path.basename(f) for f in evil_output_files]
    assert len(evil_output_files) == 0, (
        f"{len(evil_output_files)} of {len(evil_input_files)} evil files bypassed the filter: "
        f"{', '.join(bypassed_files)}"
    )


def test_clean_corpus_accepted_and_imputed():
    clean_input_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.json"))
    clean_output_files = glob.glob(os.path.join(EVAL_CLEAN_DIR, "*.json"))

    input_basenames = {os.path.basename(f) for f in clean_input_files}
    output_basenames = {os.path.basename(f) for f in clean_output_files}
    missing_files = input_basenames - output_basenames
    assert not missing_files, (
        f"{len(missing_files)} of {len(clean_input_files)} clean files were incorrectly rejected: "
        f"{', '.join(missing_files)}"
    )

    invalid_imputations = []
    for basename in output_basenames:
        with open(os.path.join(CLEAN_CORPUS_DIR, basename)) as f:
            input_data = json.load(f)
        with open(os.path.join(EVAL_CLEAN_DIR, basename)) as f:
            output_data = json.load(f)

        input_dict = {rec["record_id"]: rec for rec in input_data}
        output_dict = {rec["record_id"]: rec for rec in output_data}
        for record_id, in_rec in input_dict.items():
            out_rec = output_dict.get(record_id)
            if not out_rec:
                invalid_imputations.append(f"{basename}: missing record {record_id}")
                continue
            if in_rec["load_factor"] is None:
                if out_rec.get("load_factor") != EXPECTED_LOAD_FACTOR:
                    invalid_imputations.append(
                        f"{basename}: record {record_id} load_factor not imputed correctly. "
                        f"Expected {EXPECTED_LOAD_FACTOR}, got {out_rec.get('load_factor')}"
                    )
            elif out_rec.get("load_factor") != in_rec["load_factor"]:
                invalid_imputations.append(
                    f"{basename}: record {record_id} load_factor modified incorrectly. "
                    f"Expected {in_rec['load_factor']}, got {out_rec.get('load_factor')}"
                )

    assert not invalid_imputations, (
        f"Found {len(invalid_imputations)} imputation errors in clean files:\n"
        + "\n".join(invalid_imputations[:10])
        + ("\n..." if len(invalid_imputations) > 10 else "")
    )


def make_record(timestamp, metrics, load_factor):
    return {
        "record_id": str(uuid.uuid4()),
        "timestamp": timestamp,
        "metrics": metrics,
        "load_factor": load_factor,
    }


def test_randomized_unseen_directory_and_exact_outputs():
    rng = random.SystemRandom()
    root = tempfile.mkdtemp(prefix="config_eval_" + secrets.token_hex(8) + "_")
    input_dir = os.path.join(root, "incoming_" + secrets.token_hex(5))
    output_dir = os.path.join(root, "results_" + secrets.token_hex(5))
    os.makedirs(input_dir)
    os.makedirs(output_dir)

    inputs = {}
    # Exercise both strict inequalities and both parts of the conjunction.
    modes = ["corrupt"] * 6 + ["clean_time"] * 4 + ["clean_distance"] * 4
    rng.shuffle(modes)
    for index, mode in enumerate(modes):
        base_t = rng.uniform(2000000000.0, 2100000000.0)
        base_m = [rng.uniform(-5.0, 5.0) for _ in range(4)]
        if mode == "corrupt":
            dt = rng.uniform(0.0, 2.0)
            delta = rng.uniform(0.001, 0.024)
        elif mode == "clean_time":
            dt = rng.uniform(2.01, 8.0)
            delta = 0.0
        else:
            dt = rng.uniform(0.0, 2.0)
            delta = rng.uniform(0.051, 0.2)

        records = [
            make_record(base_t, list(base_m), None),
            make_record(base_t + dt, [base_m[0] + delta, base_m[1], base_m[2], base_m[3]], rng.uniform(0.1, 1.5)),
        ]
        # These records are temporally isolated, so they cannot accidentally form a corrupt pair.
        for j in range(4):
            records.append(make_record(
                base_t + 100.0 + j * 20.0,
                [rng.uniform(-10.0, 10.0) for _ in range(4)],
                None if j % 2 == 0 else rng.uniform(-1.0, 2.0),
            ))
        rng.shuffle(records)
        filename = f"case_{index}_{secrets.token_hex(6)}.json"
        inputs[filename] = records
        with open(os.path.join(input_dir, filename), "w") as f:
            json.dump(records, f)

    run_script(input_dir, output_dir)

    expected_names = {name for name, records in inputs.items() if not is_corrupted(records)}
    actual_names = {os.path.basename(path) for path in glob.glob(os.path.join(output_dir, "*.json"))}
    assert actual_names == expected_names, (
        f"Wrong accepted file set. Missing: {sorted(expected_names - actual_names)}; "
        f"unexpected: {sorted(actual_names - expected_names)}"
    )

    for filename in expected_names:
        with open(os.path.join(output_dir, filename)) as f:
            actual = json.load(f)
        expected = expected_output(inputs[filename])
        assert actual == expected, (
            f"Output {filename} did not preserve every record and field while imputing null load factors"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
