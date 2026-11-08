#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import math
import os
import random
import subprocess
from collections import defaultdict

OBSERVATIONS_PATH = "/home/user/observations.jsonl"
SCRIPT_PATH = "/home/user/process_observations.py"
OUTPUT_PATH = "/home/user/validated_regions.json"


def expected_observations_digest():
    rng = random.Random(42)
    regions = ["Tundra", "Rainforest", "Desert", "Taiga", "Savanna"]
    digest = hashlib.sha256()

    for _ in range(50000):
        version = rng.choice(["v1", "v2", "v3"])
        region = rng.choice(regions)
        sensor_id = f"sens_{rng.randint(1, 1000)}"

        if version == "v1":
            record = {
                "schema": "v1",
                "meta": {"state": rng.choice(["active", "inactive", "broken"]), "id": sensor_id},
                "location": {"biome": region},
                "data": {"temp_c": rng.uniform(-20, 40)},
            }
        elif version == "v2":
            record = {
                "schema": "v2",
                "device_info": {"status": rng.choice(["calibrated", "uncalibrated"]), "uuid": sensor_id},
                "geo": {"region_name": region},
                "readings": {"temperature": {"value": rng.uniform(-20, 40), "unit": "C"}},
            }
        else:
            record = {
                "schema": "v3",
                "sensor_status": "active",
                "id": sensor_id,
                "biome": region,
                "temp_f": rng.uniform(0, 100),
            }

        digest.update((json.dumps(record) + "\n").encode("utf-8"))

    return digest.hexdigest()


def file_digest(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_pydantic_models_are_used(source):
    tree = ast.parse(source, filename=SCRIPT_PATH)
    base_model_names = set()
    pydantic_module_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "pydantic":
            for alias in node.names:
                if alias.name == "BaseModel":
                    base_model_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pydantic":
                    pydantic_module_names.add(alias.asname or alias.name)

    assert base_model_names or pydantic_module_names, "The script must import and use pydantic."

    model_classes = {}
    for node in tree.body:
        if not isinstance(node, ast.ClassDef) or node.name not in {"RegionStats", "FinalOutput"}:
            continue
        is_base_model = any(
            (isinstance(base, ast.Name) and base.id in base_model_names)
            or (
                isinstance(base, ast.Attribute)
                and base.attr == "BaseModel"
                and isinstance(base.value, ast.Name)
                and base.value.id in pydantic_module_names
            )
            for base in node.bases
        )
        model_classes[node.name] = is_base_model

    assert model_classes.get("RegionStats"), "RegionStats must be a pydantic BaseModel."
    assert model_classes.get("FinalOutput"), "FinalOutput must be a pydantic BaseModel."

    validates_final_output = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id == "FinalOutput":
            validates_final_output = True
        elif (
            isinstance(node.func, ast.Attribute)
            and node.func.attr in {"model_validate", "parse_obj", "validate"}
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "FinalOutput"
        ):
            validates_final_output = True

    assert validates_final_output, "The aggregated output must be validated with FinalOutput."


def test_validated_regions_output():
    expected_digest = expected_observations_digest()
    assert os.path.isfile(OBSERVATIONS_PATH), f"Input file {OBSERVATIONS_PATH} is missing."
    assert file_digest(OBSERVATIONS_PATH) == expected_digest, "The original observations.jsonl file was modified."

    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    assert not os.path.islink(SCRIPT_PATH), f"Required script {SCRIPT_PATH} must be a regular file."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert_pydantic_models_are_used(source)

    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    try:
        completed = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
    except subprocess.TimeoutExpired:
        assert False, "process_observations.py did not complete within 5 seconds."

    assert completed.returncode == 0, (
        "process_observations.py failed.\n"
        f"stdout:\n{completed.stdout[-2000:]}\n"
        f"stderr:\n{completed.stderr[-2000:]}"
    )
    assert file_digest(OBSERVATIONS_PATH) == expected_digest, "process_observations.py modified observations.jsonl."
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    # Compute expected results from the verified, unchanged observations file.
    region_temps = defaultdict(list)
    region_sensors = defaultdict(set)

    with open(OBSERVATIONS_PATH, "r") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            schema = record.get("schema")

            if schema == "v1":
                status = record.get("meta", {}).get("state")
                if status == "active":
                    region = record.get("location", {}).get("biome")
                    temp = record.get("data", {}).get("temp_c")
                    sensor = record.get("meta", {}).get("id")
                    if region and temp is not None and sensor:
                        region_temps[region].append(temp)
                        region_sensors[region].add(sensor)
            elif schema == "v2":
                status = record.get("device_info", {}).get("status")
                if status == "calibrated":
                    region = record.get("geo", {}).get("region_name")
                    temp = record.get("readings", {}).get("temperature", {}).get("value")
                    sensor = record.get("device_info", {}).get("uuid")
                    if region and temp is not None and sensor:
                        region_temps[region].append(temp)
                        region_sensors[region].add(sensor)

    expected_results = {}
    for region in region_temps:
        avg_temp = sum(region_temps[region]) / len(region_temps[region])
        expected_results[region] = {
            "average_temperature": avg_temp,
            "unique_sensor_count": len(region_sensors[region]),
        }

    with open(OUTPUT_PATH, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {OUTPUT_PATH} is not valid JSON."

    assert "results" in actual_data, "Output JSON must contain a 'results' key."
    actual_results_list = actual_data["results"]
    assert isinstance(actual_results_list, list), "'results' must be a list."

    actual_results = {}
    for item in actual_results_list:
        region_name = item.get("region_name")
        assert region_name is not None, "Missing 'region_name' in result item."
        actual_results[region_name] = item

    for region, expected in expected_results.items():
        assert region in actual_results, f"Region '{region}' is missing from the output."
        actual = actual_results[region]

        expected_count = expected["unique_sensor_count"]
        actual_count = actual.get("unique_sensor_count")
        assert actual_count == expected_count, f"Region '{region}' unique_sensor_count mismatch: expected {expected_count}, got {actual_count}."

        expected_temp = expected["average_temperature"]
        actual_temp = actual.get("average_temperature")
        assert actual_temp is not None, f"Region '{region}' missing 'average_temperature'."
        assert math.isclose(actual_temp, expected_temp, rel_tol=1e-3, abs_tol=1e-2), \
            f"Region '{region}' average_temperature mismatch: expected {expected_temp}, got {actual_temp}."

    for region in actual_results:
        assert region in expected_results, f"Unexpected region '{region}' found in the output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
