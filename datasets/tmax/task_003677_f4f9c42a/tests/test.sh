#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import math
import os
import random
import shutil
import subprocess
import sys
import tempfile
import uuid
from decimal import Decimal, InvalidOperation

import pytest

SCRIPT = "/home/user/detect_corrupted.py"


def run_script(input_dir, output_file, expected_ids, preexisting=False):
    if preexisting:
        with open(output_file, "w", encoding="utf-8") as f:
            f.write("stale-output-must-be-replaced\n")

    result = subprocess.run(
        [sys.executable, SCRIPT, "--input-dir", input_dir, "--output", output_file],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Script exited with {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(output_file), "Script did not create the requested output file"

    with open(output_file, "r", encoding="utf-8") as f:
        actual = f.read()

    expected = "\n".join(sorted(expected_ids))
    allowed = {expected} if not expected else {expected, expected + "\n"}
    assert actual in allowed, f"Expected exact sorted IDs {sorted(expected_ids)!r}, got {actual!r}"


def test_package_installed_and_fixed():
    """Verify that the package is importable and its Python 2 import was fixed."""
    try:
        from tracker.core import Tracker
        Tracker()
    except ImportError as e:
        pytest.fail(
            "Failed to import Tracker. The package might not be installed or the "
            f"import error is not fixed: {e}"
        )
    except Exception as e:
        pytest.fail(f"Tracker instantiated with an error: {e}")


def test_script_exists():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} not found."


def test_shipped_clean_and_evil_corpora_with_disguised_filenames():
    """Retain the original corpus assertions without exposing class in copied names."""
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} not found."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} not found."

    clean_files = [p for p in os.listdir(clean_dir) if p.endswith(".json")]
    evil_files = [p for p in os.listdir(evil_dir) if p.endswith(".json")]
    assert clean_files, "Clean corpus is empty"
    assert evil_files, "Evil corpus is empty"

    with tempfile.TemporaryDirectory() as tmpdir:
        clean_input = os.path.join(tmpdir, "a")
        evil_input = os.path.join(tmpdir, "b")
        os.makedirs(clean_input)
        os.makedirs(evil_input)
        expected_clean = []

        for name in clean_files:
            src = os.path.join(clean_dir, name)
            with open(src, encoding="utf-8") as f:
                expected_clean.append(str(json.load(f)["artifact_id"]))
            shutil.copy(src, os.path.join(clean_input, uuid.uuid4().hex + ".json"))

        for name in evil_files:
            shutil.copy(
                os.path.join(evil_dir, name),
                os.path.join(evil_input, uuid.uuid4().hex + ".json"),
            )

        run_script(clean_input, os.path.join(tmpdir, "clean-out.txt"), expected_clean)
        run_script(evil_input, os.path.join(tmpdir, "evil-out.txt"), [])


def valid_number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    return not isinstance(value, float) or math.isfinite(value)


def lossless_integer_at_least_ten(value):
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return value >= 10
    if isinstance(value, float):
        return math.isfinite(value) and value.is_integer() and value >= 10
    if isinstance(value, str):
        try:
            parsed = Decimal(value)
        except InvalidOperation:
            return False
        return parsed.is_finite() and parsed == parsed.to_integral_value() and parsed >= 10
    return False


def oracle_clean(data):
    if not isinstance(data, dict) or not isinstance(data.get("artifact_id"), str):
        return False
    if data.get("schema_version") != "v2" or data.get("status") != "SUCCESS":
        return False
    metrics = data.get("metrics")
    if not isinstance(metrics, dict):
        return False
    loss = metrics.get("loss")
    accuracy = metrics.get("accuracy")
    if not valid_number(loss) or loss > 2.0:
        return False
    if not valid_number(accuracy) or accuracy < 0.5:
        return False

    candidates = []
    if "model_size_mb" in data:
        candidates.append(data["model_size_mb"])
    artifacts = data.get("artifacts")
    if isinstance(artifacts, dict) and "model_size_mb" in artifacts:
        candidates.append(artifacts["model_size_mb"])
    return any(lossless_integer_at_least_ten(value) for value in candidates)


def random_id():
    return "artifact-" + uuid.uuid4().hex


def base_record(size=10, nested=False, loss=1.0, accuracy=0.75):
    record = {
        "artifact_id": random_id(),
        "schema_version": "v2",
        "status": "SUCCESS",
        "metrics": {"loss": loss, "accuracy": accuracy},
    }
    if nested:
        record["artifacts"] = {"model_size_mb": size}
    else:
        record["model_size_mb"] = size
    return record


def set_only_size(record, value):
    record.pop("model_size_mb", None)
    record.pop("artifacts", None)
    record["model_size_mb"] = value


def test_generated_hidden_mixed_corpus_edge_cases_and_sorting():
    rng = random.SystemRandom()
    records = []

    # Explicit valid boundaries and lossless integer representations.
    records.extend([
        base_record(size=10, loss=2.0, accuracy=0.5),
        base_record(size=10.0, nested=True, loss=-3.25, accuracy=1.0),
        base_record(size="10", loss=0, accuracy=0.5),
    ])
    for _ in range(30):
        size = rng.choice([rng.randint(10, 500), float(rng.randint(10, 500)), str(rng.randint(10, 500))])
        records.append(base_record(
            size=size,
            nested=rng.choice([True, False]),
            loss=rng.uniform(-5.0, 2.0),
            accuracy=rng.uniform(0.5, 1.5),
        ))

    corruptions = [
        "schema", "status", "metrics_missing", "loss_missing", "loss_high",
        "loss_nan", "loss_inf", "loss_string", "loss_bool", "accuracy_missing",
        "accuracy_low", "accuracy_nan", "accuracy_inf", "accuracy_string",
        "accuracy_bool", "size_missing", "size_low", "size_fraction",
        "size_nan", "size_bool", "size_bad_string", "artifacts_wrong_type",
    ]

    for mode in corruptions:
        record = base_record(size=25, nested=rng.choice([True, False]))
        if mode == "schema":
            record["schema_version"] = "v1"
        elif mode == "status":
            record["status"] = "FAILED"
        elif mode == "metrics_missing":
            record.pop("metrics")
        elif mode == "loss_missing":
            record["metrics"].pop("loss")
        elif mode == "loss_high":
            record["metrics"]["loss"] = 2.000001
        elif mode == "loss_nan":
            record["metrics"]["loss"] = float("nan")
        elif mode == "loss_inf":
            record["metrics"]["loss"] = float("inf")
        elif mode == "loss_string":
            record["metrics"]["loss"] = "1.0"
        elif mode == "loss_bool":
            record["metrics"]["loss"] = True
        elif mode == "accuracy_missing":
            record["metrics"].pop("accuracy")
        elif mode == "accuracy_low":
            record["metrics"]["accuracy"] = 0.499999
        elif mode == "accuracy_nan":
            record["metrics"]["accuracy"] = float("nan")
        elif mode == "accuracy_inf":
            record["metrics"]["accuracy"] = float("inf")
        elif mode == "accuracy_string":
            record["metrics"]["accuracy"] = "0.9"
        elif mode == "accuracy_bool":
            record["metrics"]["accuracy"] = True
        elif mode == "size_missing":
            record.pop("model_size_mb", None)
            record.pop("artifacts", None)
        elif mode == "size_low":
            set_only_size(record, 9)
        elif mode == "size_fraction":
            set_only_size(record, 10.25)
        elif mode == "size_nan":
            set_only_size(record, float("nan"))
        elif mode == "size_bool":
            set_only_size(record, True)
        elif mode == "size_bad_string":
            set_only_size(record, "ten")
        elif mode == "artifacts_wrong_type":
            record.pop("model_size_mb", None)
            record["artifacts"] = [25]
        records.append(record)

    rng.shuffle(records)
    expected = sorted(record["artifact_id"] for record in records if oracle_clean(record))

    with tempfile.TemporaryDirectory() as tmpdir:
        input_dir = os.path.join(tmpdir, uuid.uuid4().hex)
        os.makedirs(input_dir)

        for record in records:
            filename = uuid.uuid4().hex + ".json"
            with open(os.path.join(input_dir, filename), "w", encoding="utf-8") as f:
                json.dump(record, f, allow_nan=True)

        # Malformed JSON, valid non-object JSON, and a clean-looking non-JSON file.
        malformed_id = random_id()
        with open(os.path.join(input_dir, uuid.uuid4().hex + ".json"), "w", encoding="utf-8") as f:
            f.write('{"artifact_id": "' + malformed_id + '", "schema_version": "v2",')
        with open(os.path.join(input_dir, uuid.uuid4().hex + ".json"), "w", encoding="utf-8") as f:
            f.write("not json at all")
        with open(os.path.join(input_dir, uuid.uuid4().hex + ".json"), "w", encoding="utf-8") as f:
            json.dump([], f)
        with open(os.path.join(input_dir, uuid.uuid4().hex + ".json"), "w", encoding="utf-8") as f:
            json.dump(None, f)
        with open(os.path.join(input_dir, uuid.uuid4().hex + ".txt"), "w", encoding="utf-8") as f:
            json.dump(base_record(), f)

        run_script(
            input_dir,
            os.path.join(tmpdir, "result.csv"),
            expected,
            preexisting=True,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
