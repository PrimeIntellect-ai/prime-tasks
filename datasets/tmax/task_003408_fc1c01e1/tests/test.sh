#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import random
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/tests/oracle_pipeline.py"
AGENT_PATH = "/home/user/pipeline.py"
TINYDB_ROOT = "/app/tinydb-4.8.0"
TINYDB_STORAGES_PATH = "/app/tinydb-4.8.0/tinydb/storages.py"
EXPERIMENTS_DB_PATH = "/home/user/experiments.json"


def read_records():
    assert os.path.isfile(EXPERIMENTS_DB_PATH), (
        f"Experiments DB {EXPERIMENTS_DB_PATH} was not created."
    )
    with open(EXPERIMENTS_DB_PATH, "r") as f:
        try:
            db_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{EXPERIMENTS_DB_PATH} is not valid JSON.")

    assert "_default" in db_data, "TinyDB should have a '_default' table."
    records = db_data["_default"]
    assert isinstance(records, dict), "TinyDB '_default' table must contain documents."
    return records


def test_tinydb_fixed():
    """Verify that the vendored tinydb bug is fixed and that it is installed."""
    assert os.path.isfile(TINYDB_STORAGES_PATH), "tinydb storages.py is missing."
    with open(TINYDB_STORAGES_PATH, "r") as f:
        content = f.read()
    assert "import jsonn" not in content, (
        "The bug 'import jsonn' is still present in tinydb/storages.py."
    )

    result = subprocess.run(
        [
            "python3",
            "-c",
            "import os, tinydb, tinydb.storages; "
            "print(os.path.realpath(tinydb.storages.__file__))",
        ],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"The fixed tinydb cannot be imported:\n{result.stderr}"
    installed_storage = result.stdout.strip()
    assert os.path.commonpath([installed_storage, TINYDB_ROOT]) == TINYDB_ROOT, (
        "The imported tinydb is not the required vendored copy."
    )


def test_pipeline_exists():
    """Verify the agent script exists and is not the reference implementation."""
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."
    assert os.path.isfile(ORACLE_PATH), f"Verifier oracle {ORACLE_PATH} does not exist."
    with open(AGENT_PATH, "rb") as agent_file, open(ORACLE_PATH, "rb") as oracle_file:
        assert agent_file.read() != oracle_file.read(), (
            "The submitted pipeline must not be a byte-identical copy of the reference."
        )


def test_fuzz_equivalence_and_logging():
    """Exercise the pipeline and validate output and TinyDB logging for every run."""
    random.seed(42)

    if os.path.exists(EXPERIMENTS_DB_PATH):
        os.remove(EXPERIMENTS_DB_PATH)

    with tempfile.TemporaryDirectory() as tmpdir:
        hook_dir = os.path.join(tmpdir, "hook")
        os.mkdir(hook_dir)
        marker_path = os.path.join(tmpdir, "tinydb_calls.jsonl")

        # Instrument TinyDB in the agent subprocess so manually writing TinyDB-shaped
        # JSON cannot satisfy the experiment-tracking requirement.
        with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
            f.write(
                "import json, os\n"
                "from tinydb.table import Table\n"
                "_original_insert = Table.insert\n"
                "def _tracked_insert(self, document):\n"
                "    marker = os.environ.get('TINYDB_TRACK_MARKER')\n"
                "    if marker:\n"
                "        with open(marker, 'a') as out:\n"
                "            out.write(json.dumps(dict(document), sort_keys=True) + '\\\\n')\n"
                "    return _original_insert(self, document)\n"
                "Table.insert = _tracked_insert\n"
            )

        for i in range(50):
            sensors_path = os.path.join(tmpdir, f"sensors_{i}.csv")
            predictions_path = os.path.join(tmpdir, f"predictions_{i}.csv")

            num_sensors = random.randint(50, 200)
            with open(sensors_path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["id", "actual_value"])
                for _ in range(num_sensors):
                    writer.writerow([
                        random.randint(1, 1000),
                        round(random.uniform(0.0, 100.0), 2),
                    ])

            num_preds = random.randint(50, 200)
            with open(predictions_path, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(["id", "pred_value", "threshold"])
                for _ in range(num_preds):
                    writer.writerow([
                        random.randint(1, 1000),
                        round(random.uniform(0.0, 100.0), 2),
                        round(random.uniform(0.5, 5.0), 2),
                    ])

            oracle_res = subprocess.run(
                ["python3", ORACLE_PATH, sensors_path, predictions_path],
                capture_output=True,
                text=True,
            )
            assert oracle_res.returncode == 0, (
                f"Oracle failed on iteration {i}:\n{oracle_res.stderr}"
            )

            expected_rows = list(csv.DictReader(io.StringIO(oracle_res.stdout)))
            expected_record = {
                "sensors_file": sensors_path,
                "predictions_file": predictions_path,
                "valid_count": len(expected_rows),
            }

            before_records = read_records() if os.path.exists(EXPERIMENTS_DB_PATH) else {}
            before_keys = set(before_records)
            if os.path.exists(marker_path):
                os.remove(marker_path)

            env = os.environ.copy()
            env["TINYDB_TRACK_MARKER"] = marker_path
            env["PYTHONPATH"] = hook_dir + os.pathsep + env.get("PYTHONPATH", "")
            agent_res = subprocess.run(
                ["python3", AGENT_PATH, sensors_path, predictions_path],
                capture_output=True,
                text=True,
                env=env,
            )
            assert agent_res.returncode == 0, (
                f"Agent script failed on iteration {i}:\n{agent_res.stderr}"
            )
            assert agent_res.stdout == oracle_res.stdout, (
                f"Output mismatch on iteration {i}.\n"
                f"Sensors file: {sensors_path}\n"
                f"Predictions file: {predictions_path}\n"
                f"Expected STDOUT:\n{oracle_res.stdout}\n"
                f"Got STDOUT:\n{agent_res.stdout}"
            )

            assert os.path.isfile(marker_path), (
                f"Iteration {i} did not insert its experiment document using TinyDB."
            )
            with open(marker_path, "r") as f:
                calls = [json.loads(line) for line in f if line.strip()]
            assert expected_record in calls, (
                f"Iteration {i} did not pass the required document to TinyDB.insert."
            )

            after_records = read_records()
            new_keys = set(after_records) - before_keys
            assert len(after_records) == len(before_records) + 1 and len(new_keys) == 1, (
                f"Iteration {i} must add exactly one experiment record."
            )
            new_record = after_records[new_keys.pop()]
            assert new_record == expected_record, (
                f"Incorrect experiment record on iteration {i}.\n"
                f"Expected: {expected_record!r}\nGot: {new_record!r}"
            )


def test_experiments_logged():
    """Retain the final-state checks for the TinyDB experiment database."""
    records = read_records()
    assert len(records) > 0, "No experiment records found in the database."

    last_record = list(records.values())[-1]
    assert "sensors_file" in last_record, "Missing 'sensors_file' in experiment record."
    assert "predictions_file" in last_record, (
        "Missing 'predictions_file' in experiment record."
    )
    assert "valid_count" in last_record, "Missing 'valid_count' in experiment record."
    assert isinstance(last_record["valid_count"], int), (
        "'valid_count' must be an integer."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
