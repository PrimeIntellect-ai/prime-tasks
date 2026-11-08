#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import subprocess

import jsonschema
import pandas as pd
from sklearn.datasets import make_regression
from sklearn.linear_model import BayesianRidge
from sklearn.model_selection import GridSearchCV

SCRIPT = "/home/user/experiment.py"
DATA = "/home/user/data.csv"
SCHEMA = "/home/user/schema.json"
ARTIFACT = "/home/user/artifact.json"
GRID = [1e-6, 1e-5, 1e-4]


def run_script():
    return subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )


def load_strict_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.loads(
            f.read(),
            parse_constant=lambda value: (_ for _ in ()).throw(
                ValueError(f"Invalid JSON constant: {value}")
            ),
        )


def expected_result_from_data():
    df = pd.read_csv(DATA)
    X = df.drop(columns=["target"])
    y = df["target"]
    search = GridSearchCV(
        BayesianRidge(),
        {"alpha_1": GRID, "lambda_1": GRID},
        cv=3,
    )
    search.fit(X, y)
    return {
        "model": "BayesianRidge",
        "best_alpha_1": float(search.best_params_["alpha_1"]),
        "best_lambda_1": float(search.best_params_["lambda_1"]),
        "cv_score": float(search.best_score_),
    }


def assert_exact_result(artifact, expected):
    assert artifact["model"] == expected["model"]
    assert artifact["best_alpha_1"] == expected["best_alpha_1"]
    assert artifact["best_lambda_1"] == expected["best_lambda_1"]
    assert math.isclose(
        artifact["cv_score"], expected["cv_score"], rel_tol=1e-10, abs_tol=1e-12
    ), f"cv_score {artifact['cv_score']} does not match GridSearchCV result {expected['cv_score']}"


def test_script_execution_grid_search_and_schema_validation():
    assert os.path.isfile(SCRIPT), f"Expected experiment script {SCRIPT} does not exist."

    with open(DATA, "rb") as f:
        original_data = f.read()
    with open(SCHEMA, "rb") as f:
        original_schema = f.read()

    final_run = None
    try:
        # Derive the expected answer independently, then require the submitted
        # script to regenerate the artifact from the supplied files.
        expected = expected_result_from_data()
        if os.path.exists(ARTIFACT):
            os.remove(ARTIFACT)
        result = run_script()
        assert result.returncode == 0, result.stdout + "\n" + result.stderr
        assert os.path.isfile(ARTIFACT), f"Expected artifact file {ARTIFACT} does not exist."

        artifact = load_strict_json(ARTIFACT)
        assert isinstance(artifact, dict), "Artifact must be a JSON object (dictionary)."
        expected_keys = {"model", "best_alpha_1", "best_lambda_1", "cv_score"}
        actual_keys = set(artifact.keys())
        assert actual_keys == expected_keys, (
            f"Artifact keys {actual_keys} do not exactly match expected keys "
            f"{expected_keys}. No additional properties are allowed."
        )
        assert artifact["model"] == "BayesianRidge", (
            f"Expected model 'BayesianRidge', got {artifact['model']}."
        )
        assert isinstance(artifact["best_alpha_1"], (int, float)), "best_alpha_1 must be a number."
        assert artifact["best_alpha_1"] in GRID, (
            f"best_alpha_1 {artifact['best_alpha_1']} is not in the expected grid."
        )
        assert isinstance(artifact["best_lambda_1"], (int, float)), "best_lambda_1 must be a number."
        assert artifact["best_lambda_1"] in GRID, (
            f"best_lambda_1 {artifact['best_lambda_1']} is not in the expected grid."
        )
        assert isinstance(artifact["cv_score"], (int, float)), "cv_score must be a number."
        assert 0.9 < artifact["cv_score"] <= 1.0, (
            f"cv_score {artifact['cv_score']} is out of expected range (0.9, 1.0]."
        )
        schema = json.loads(original_schema.decode("utf-8"))
        jsonschema.validate(artifact, schema)
        assert_exact_result(artifact, expected)

        # Replace data.csv with an independently generated probe dataset. This
        # prevents a hardcoded artifact for the image's original data from passing.
        X, y = make_regression(
            n_samples=93,
            n_features=5,
            noise=12.0,
            random_state=731,
        )
        probe = pd.DataFrame(X, columns=["p1", "p2", "p3", "p4", "p5"])
        probe["target"] = y
        probe.to_csv(DATA, index=False)
        with open(SCHEMA, "wb") as f:
            f.write(original_schema)
        probe_expected = expected_result_from_data()
        if os.path.exists(ARTIFACT):
            os.remove(ARTIFACT)
        result = run_script()
        assert result.returncode == 0, result.stdout + "\n" + result.stderr
        assert os.path.isfile(ARTIFACT), "Script did not generate an artifact for probe data."
        probe_artifact = load_strict_json(ARTIFACT)
        jsonschema.validate(probe_artifact, schema)
        assert_exact_result(probe_artifact, probe_expected)

        # A schema that rejects the otherwise valid result must prevent artifact
        # creation, demonstrating that schema enforcement occurs before saving.
        rejecting_schema = json.loads(original_schema.decode("utf-8"))
        rejecting_schema["properties"]["cv_score"]["maximum"] = -1e100
        with open(SCHEMA, "w", encoding="utf-8") as f:
            json.dump(rejecting_schema, f)
        if os.path.exists(ARTIFACT):
            os.remove(ARTIFACT)
        run_script()
        assert not os.path.exists(ARTIFACT), (
            "experiment.py created artifact.json even though schema validation should fail."
        )
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)
        with open(SCHEMA, "wb") as f:
            f.write(original_schema)
        if os.path.exists(ARTIFACT):
            os.remove(ARTIFACT)
        final_run = run_script()

    assert final_run.returncode == 0, final_run.stdout + "\n" + final_run.stderr
    assert os.path.isfile(ARTIFACT), "Script did not restore the final artifact from original data."
    final_artifact = load_strict_json(ARTIFACT)
    jsonschema.validate(final_artifact, json.loads(original_schema.decode("utf-8")))
    assert_exact_result(final_artifact, expected_result_from_data())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
