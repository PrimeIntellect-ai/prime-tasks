#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import subprocess
import uuid
import pytest


def test_pipeline_json():
    pipeline_path = "/home/user/pipeline.json"
    assert os.path.isfile(pipeline_path), f"File not found: {pipeline_path}"

    with open(pipeline_path, 'r') as f:
        try:
            pipeline = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {pipeline_path}")

    assert isinstance(pipeline, list), f"Pipeline must be a JSON array in {pipeline_path}"
    assert len(pipeline) >= 2, f"Pipeline must have at least 2 stages in {pipeline_path}"
    assert isinstance(pipeline[0], dict) and "$match" in pipeline[0], "The pipeline must start with a $match stage"

    # Find $match and $graphLookup stages
    match_stage = None
    graph_lookup_stage = None

    for stage in pipeline:
        if "$match" in stage:
            match_stage = stage["$match"]
        elif "$graphLookup" in stage:
            graph_lookup_stage = stage["$graphLookup"]

    assert match_stage is not None, "Missing $match stage in pipeline"
    assert match_stage.get("package_name") == "gateway-api", "The $match stage must filter by package_name 'gateway-api'"

    assert graph_lookup_stage is not None, "Missing $graphLookup stage in pipeline"
    gl = graph_lookup_stage
    assert gl.get("from") == "packages", "$graphLookup 'from' field must be 'packages'"
    assert gl.get("startWith") == "$depends_on", "$graphLookup 'startWith' field must be '$depends_on'"
    assert gl.get("connectFromField") == "depends_on", "$graphLookup 'connectFromField' field must be 'depends_on'"
    assert gl.get("connectToField") == "package_name", "$graphLookup 'connectToField' field must be 'package_name'"
    assert gl.get("as") == "transitive_dependencies", "$graphLookup 'as' field must be 'transitive_dependencies'"
    assert gl.get("maxDepth") == 5, "$graphLookup 'maxDepth' field must be 5"


def test_index_strategy_json():
    index_path = "/home/user/index_strategy.json"
    assert os.path.isfile(index_path), f"File not found: {index_path}"

    with open(index_path, 'r') as f:
        try:
            idx = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {index_path}")

    assert isinstance(idx, dict), f"Index strategy must be a JSON object in {index_path}"
    assert "package_name" in idx, "Index strategy must target the 'package_name' field"
    assert idx["package_name"] in [1, -1], "Index strategy value for 'package_name' must be 1 or -1"


def test_validated_output_json():
    output_path = "/home/user/validated_output.json"
    assert os.path.isfile(output_path), f"File not found: {output_path}. Did you run validate.py?"

    with open(output_path, 'r') as f:
        try:
            out = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {output_path}")

    # The mock output is valid according to the schema, so the output should match the mock output
    assert isinstance(out, list), f"Validated output should be a JSON array, got {type(out).__name__}"
    assert len(out) > 0, "Validated output array is empty"

    first_item = out[0]
    assert first_item.get("package_name") == "gateway-api", "Validated output does not match expected mock output content"
    assert "transitive_dependencies" in first_item, "Missing transitive_dependencies in validated output"
    assert len(first_item["transitive_dependencies"]) == 2, "Incorrect number of transitive dependencies in validated output"

    with open("/home/user/mock_output.json", "r") as f:
        mock = json.load(f)
    assert out == mock, "Validated output must contain the mock output identically"


def test_validate_script_uses_jsonschema_and_handles_dynamic_inputs():
    script_path = "/home/user/validate.py"
    assert os.path.isfile(script_path), f"File not found: {script_path}"

    with open(script_path, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=script_path)
    except SyntaxError as exc:
        pytest.fail(f"Invalid Python in {script_path}: {exc}")

    imports_jsonschema = any(
        (isinstance(node, ast.Import) and any(alias.name == "jsonschema" or alias.name.startswith("jsonschema.") for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module is not None and (node.module == "jsonschema" or node.module.startswith("jsonschema.")))
        for node in ast.walk(tree)
    )
    assert imports_jsonschema, "validate.py must import and use the jsonschema library"

    catches_validation_error = any(
        isinstance(node, ast.ExceptHandler)
        and node.type is not None
        and "ValidationError" in ast.unparse(node.type)
        for node in ast.walk(tree)
    )
    assert catches_validation_error, "validate.py must catch jsonschema.exceptions.ValidationError"

    paths = [
        "/home/user/schema.json",
        "/home/user/mock_output.json",
        "/home/user/validated_output.json",
    ]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    token = "verification-" + uuid.uuid4().hex
    schema = {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "type": "object",
        "properties": {
            "token": {"type": "string", "const": token},
            "count": {"type": "integer", "minimum": 3},
        },
        "required": ["token", "count"],
        "additionalProperties": False,
    }
    valid_mock = {"token": token, "count": 7}
    invalid_mock = {"token": token, "count": 1}

    try:
        with open("/home/user/schema.json", "w", encoding="utf-8") as f:
            json.dump(schema, f)
        with open("/home/user/mock_output.json", "w", encoding="utf-8") as f:
            json.dump(valid_mock, f)
        if os.path.exists("/home/user/validated_output.json"):
            os.remove("/home/user/validated_output.json")

        result = subprocess.run(
            ["python3", script_path], capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, f"validate.py failed on valid input: {result.stderr}"
        assert os.path.isfile("/home/user/validated_output.json"), "validate.py did not create validated_output.json"
        with open("/home/user/validated_output.json", "r", encoding="utf-8") as f:
            valid_result = json.load(f)
        assert valid_result == valid_mock, "validate.py must write valid mock output unchanged"

        with open("/home/user/mock_output.json", "w", encoding="utf-8") as f:
            json.dump(invalid_mock, f)
        os.remove("/home/user/validated_output.json")

        result = subprocess.run(
            ["python3", script_path], capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, f"validate.py did not handle validation failure: {result.stderr}"
        assert os.path.isfile("/home/user/validated_output.json"), "validate.py did not write an invalid-status output"
        with open("/home/user/validated_output.json", "r", encoding="utf-8") as f:
            invalid_result = json.load(f)
        assert isinstance(invalid_result, dict), "Invalid data must produce a JSON object"
        assert invalid_result.get("status") == "invalid", "Invalid data must produce status 'invalid'"
        assert isinstance(invalid_result.get("reason"), str) and invalid_result["reason"], "Invalid data must include a nonempty validation reason"
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
