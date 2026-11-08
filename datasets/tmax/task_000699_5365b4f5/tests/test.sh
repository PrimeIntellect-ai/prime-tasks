#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import importlib.util
import json
import os
import secrets

import pandas as pd


def test_test_result_txt():
    path = "/home/user/test_result.txt"
    assert os.path.exists(path), f"File {path} is missing. The test script must create it."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "REPRODUCIBILITY_PASSED", f"Expected 'REPRODUCIBILITY_PASSED' in {path}, got '{content}'"


def test_features_csv_format():
    path = "/home/user/features.csv"
    assert os.path.exists(path), f"File {path} is missing. The pipeline should have generated it."

    expected_category_ids = ["1", "2", "3", "-1", "-1"]
    actual_category_ids = []

    with open(path, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "features.csv is empty."
        assert "category_id" in header, "features.csv is missing 'category_id' column."

        cat_idx = header.index("category_id")
        for row in reader:
            if len(row) > cat_idx:
                actual_category_ids.append(row[cat_idx])

    assert actual_category_ids == expected_category_ids, (
        f"Expected category_id values to be {expected_category_ids}, "
        f"but got {actual_category_ids}. Make sure they are integers and not floats (e.g. no '.0')."
    )


def test_test_pipeline_script_exists():
    path = "/home/user/test_pipeline.py"
    assert os.path.exists(path), f"File {path} is missing. You need to create the test script."


def test_test_pipeline_imports_and_calls_pipeline():
    path = "/home/user/test_pipeline.py"
    with open(path, "r") as f:
        tree = ast.parse(f.read(), filename=path)

    module_aliases = set()
    function_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pipeline":
                    module_aliases.add(alias.asname or "pipeline")
        elif isinstance(node, ast.ImportFrom) and node.module == "pipeline":
            for alias in node.names:
                if alias.name == "run_pipeline":
                    function_aliases.add(alias.asname or "run_pipeline")

    called = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in function_aliases:
            called = True
        elif (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == "run_pipeline"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in module_aliases
        ):
            called = True

    assert called, "test_pipeline.py must import and call pipeline.run_pipeline()."


def test_pipeline_on_derived_input():
    data_path = "/home/user/data.csv"
    mapping_path = "/home/user/mapping.json"
    features_path = "/home/user/features.csv"
    pipeline_path = "/home/user/pipeline.py"

    paths = [data_path, mapping_path, features_path]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    base = secrets.randbelow(1000000) + 1000
    categories = [base + i for i in range(5)]
    mapping = {
        str(categories[0]): 7,
        str(categories[1]): -4,
        str(categories[3]): 12,
    }
    expected = [mapping.get(str(category), -1) for category in categories]

    try:
        with open(data_path, "w") as f:
            f.write("sample_id,category_id,value\n")
            for i, category in enumerate(categories, 1):
                f.write(f"{i},{category},{i / 10}\n")
        with open(mapping_path, "w") as f:
            json.dump(mapping, f)
        if os.path.exists(features_path):
            os.remove(features_path)

        spec = importlib.util.spec_from_file_location(
            f"submitted_pipeline_{secrets.token_hex(8)}", pipeline_path
        )
        assert spec is not None and spec.loader is not None, "Unable to import pipeline.py"
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        assert callable(getattr(module, "run_pipeline", None)), "pipeline.py must define run_pipeline()"
        module.run_pipeline()

        assert os.path.exists(features_path), "run_pipeline() did not create features.csv"
        generated = pd.read_csv(features_path)
        assert "category_id" in generated.columns
        assert generated["category_id"].dtype == "int64"
        assert generated["category_id"].tolist() == expected

        with open(features_path, newline="") as f:
            reader = csv.DictReader(f)
            raw_values = [row["category_id"] for row in reader]
        assert raw_values == [str(value) for value in expected], (
            "Generated category_id values must use integer string representations."
        )
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

passed=1
rm -f /home/user/features.csv /home/user/test_result.txt
if ! cd /home/user && python3 /home/user/test_pipeline.py; then
    passed=0
fi

if [ "$passed" -eq 1 ]; then
    if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
        passed=0
    fi
fi

echo "$passed" > /logs/verifier/reward.txt
