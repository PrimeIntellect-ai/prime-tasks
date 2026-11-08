#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import csv
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/staged_rollout.py"
PLAN_PATH = "/home/user/plan.csv"
MANIFEST_DIR = "/home/user/manifests"
OUTPUT_DIR = "/home/user/deploy_out"


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_frontend_canary_output():
    output_path = "/home/user/deploy_out/frontend_canary.json"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read()
        try:
            data = json.loads(content)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} is not valid JSON.")

    replicas = data.get("spec", {}).get("replicas")
    assert replicas == 1, f"Expected replicas to be 1 in {output_path}, but got {replicas}."

    try:
        image = data["spec"]["template"]["spec"]["containers"][0]["image"]
    except KeyError:
        pytest.fail(f"The file {output_path} does not have the expected container image structure.")

    expected_image = "registry.local/frontend:2.0-canary"
    assert image == expected_image, f"Expected image to be '{expected_image}' in {output_path}, but got '{image}'."


def test_backend_production_output():
    output_path = "/home/user/deploy_out/backend_production.json"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

    with open(output_path, "r") as f:
        content = f.read()
        try:
            data = json.loads(content)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} is not valid JSON.")

    replicas = data.get("spec", {}).get("replicas")
    assert replicas == 5, f"Expected replicas to be 5 in {output_path}, but got {replicas}."

    try:
        image = data["spec"]["template"]["spec"]["containers"][0]["image"]
    except KeyError:
        pytest.fail(f"The file {output_path} does not have the expected container image structure.")

    expected_image = "registry.local/backend:1.5"
    assert image == expected_image, f"Expected image to be '{expected_image}' in {output_path}, but got '{image}'."


def test_json_indentation():
    for output_path in [
        "/home/user/deploy_out/frontend_canary.json",
        "/home/user/deploy_out/backend_production.json",
    ]:
        if os.path.isfile(output_path):
            with open(output_path, "r") as f:
                lines = f.readlines()
                if len(lines) > 1:
                    second_line = lines[1]
                    leading_spaces = len(second_line) - len(second_line.lstrip(" "))
                    assert leading_spaces == 2, f"Expected 2 spaces indentation in {output_path}, but found {leading_spaces} spaces."


def test_script_dynamically_processes_plan_and_preserves_manifests():
    token = secrets.token_hex(6)
    cases = [
        (f"alpha_{token}", "canary", f"registry.test/service-a:{token}"),
        (f"beta_{token}", "production", f"registry.test/service-b:{token}-canary"),
        (f"gamma_{token}", "canary", f"registry.test/service-c:{token}-canary"),
        (f"delta_{token}", "production", f"registry.test/service-d:{token}"),
    ]

    backup_root = tempfile.mkdtemp(prefix="rollout-verifier-")
    backup_manifests = os.path.join(backup_root, "manifests")
    backup_outputs = os.path.join(backup_root, "deploy_out")
    backup_plan = os.path.join(backup_root, "plan.csv")
    shutil.copytree(MANIFEST_DIR, backup_manifests)
    shutil.copytree(OUTPUT_DIR, backup_outputs)
    shutil.copy2(PLAN_PATH, backup_plan)

    try:
        shutil.rmtree(MANIFEST_DIR)
        shutil.rmtree(OUTPUT_DIR)
        os.makedirs(MANIFEST_DIR)
        os.makedirs(OUTPUT_DIR)

        source_manifests = {}
        for index, (app_name, stage, image) in enumerate(cases):
            manifest = {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {
                    "name": app_name,
                    "labels": {"verification-token": token, "case": str(index)},
                    "annotations": {"preserve-me": f"value-{index}-{token}"},
                },
                "spec": {
                    "replicas": 20 + index,
                    "strategy": {"type": "RollingUpdate", "marker": token},
                    "template": {
                        "metadata": {"labels": {"app": app_name}},
                        "spec": {
                            "containers": [
                                {
                                    "name": f"primary-{index}",
                                    "image": image,
                                    "env": [{"name": "TOKEN", "value": token}],
                                },
                                {
                                    "name": "sidecar",
                                    "image": f"registry.test/sidecar:{token}",
                                },
                            ],
                            "nodeSelector": {"verification": token},
                        },
                    },
                },
                "verificationExtra": {"nested": [1, {"token": token}, 3]},
            }
            source_manifests[app_name] = manifest
            with open(os.path.join(MANIFEST_DIR, app_name + ".json"), "w") as f:
                json.dump(manifest, f, indent=2)

        with open(PLAN_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["app_name", "stage"])
            for app_name, stage, _ in cases:
                writer.writerow([app_name, stage])

        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )

        for app_name, stage, original_image in cases:
            output_path = os.path.join(OUTPUT_DIR, f"{app_name}_{stage}.json")
            assert os.path.isfile(output_path), f"The script did not create {output_path}."

            with open(output_path, "r") as f:
                content = f.read()
            try:
                actual = json.loads(content)
            except json.JSONDecodeError as exc:
                pytest.fail(f"The generated file {output_path} is not valid JSON: {exc}")

            expected = copy.deepcopy(source_manifests[app_name])
            if stage == "canary":
                expected["spec"]["replicas"] = 1
                expected_image = original_image if original_image.endswith("-canary") else original_image + "-canary"
            else:
                expected["spec"]["replicas"] = 5
                expected_image = original_image[:-len("-canary")] if original_image.endswith("-canary") else original_image
            expected["spec"]["template"]["spec"]["containers"][0]["image"] = expected_image

            assert actual == expected, (
                f"{output_path} must preserve the complete source manifest and only apply "
                f"the required {stage} replica and first-container image changes."
            )

            lines = content.splitlines()
            assert len(lines) > 1, f"Expected pretty-printed JSON in {output_path}."
            leading_spaces = len(lines[1]) - len(lines[1].lstrip(" "))
            assert leading_spaces == 2, f"Expected 2 spaces indentation in {output_path}, but found {leading_spaces} spaces."
    finally:
        if os.path.exists(MANIFEST_DIR):
            shutil.rmtree(MANIFEST_DIR)
        if os.path.exists(OUTPUT_DIR):
            shutil.rmtree(OUTPUT_DIR)
        shutil.copytree(backup_manifests, MANIFEST_DIR)
        shutil.copytree(backup_outputs, OUTPUT_DIR)
        shutil.copy2(backup_plan, PLAN_PATH)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
