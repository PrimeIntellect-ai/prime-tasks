#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import stat
import subprocess
import uuid
from collections import Counter

import pytest

SCRIPT = "/home/user/run_operator.sh"
PROJECT = "/app/k8s-manifest-gen"
BINARY = "/app/k8s-manifest-gen/target/release/k8s-manifest-gen"
CONFIGS = "/home/user/configs"
OUTPUT = "/home/user/output/manifests.yaml"


def run_checked(command, cwd=None, timeout=180):
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command {command!r} failed with exit code {result.returncode}:\n{result.stdout}"
    )
    return result


def expected_services():
    names = []
    for filename in os.listdir(CONFIGS):
        path = os.path.join(CONFIGS, filename)
        if os.path.isfile(path) and filename.endswith(".json"):
            with open(path, encoding="utf-8") as handle:
                config = json.load(handle)
            assert isinstance(config.get("name"), str) and config["name"], (
                f"Configuration {path} has no valid service name"
            )
            names.append(config["name"])
    return names


def deployment_names(text):
    names = []
    for document in re.split(r"(?m)^\s*---\s*$", text):
        if not document.strip():
            continue
        kinds = re.findall(r"(?m)^kind:\s*([^#\n]+?)\s*$", document)
        if "Deployment" not in kinds:
            continue
        assert kinds.count("Deployment") == 1, "Malformed Deployment document"
        match = re.search(
            r"(?ms)^metadata:\s*(?:#.*)?\n(?P<body>(?:^[ \t]+.*(?:\n|$))*)",
            document,
        )
        assert match, "Deployment is missing metadata"
        name_match = re.search(r"(?m)^[ \t]+name:\s*([^#\n]+?)\s*$", match.group("body"))
        assert name_match, "Deployment metadata is missing a name"
        names.append(name_match.group(1).strip().strip("'\""))
    return names


def assert_manifest(expected):
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT, encoding="utf-8") as handle:
        contents = handle.read()
    actual = deployment_names(contents)
    assert Counter(actual) == Counter(expected), (
        "Manifest must contain exactly one Deployment for every configured service. "
        f"Expected {Counter(expected)}, got {Counter(actual)}"
    )
    assert len(actual) == len(expected), "Duplicate Deployment resources were generated"
    return contents


@pytest.fixture(scope="session", autouse=True)
def exercise_pipeline():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.stat(SCRIPT).st_mode & stat.S_IXUSR, f"Script {SCRIPT} is not executable."

    # Add an unpredictable service so hard-coded or stale output cannot pass.
    service = "verify-" + uuid.uuid4().hex
    dynamic_config = os.path.join(CONFIGS, service + ".json")
    with open(dynamic_config, "w", encoding="utf-8") as handle:
        json.dump({"name": service}, handle)

    expected = expected_services()

    # Independently verify that the repaired Makefile's build target succeeds.
    run_checked(["make", "build"], cwd=PROJECT)
    assert os.path.isfile(BINARY), f"make build did not produce {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Built binary {BINARY} is not executable"

    # Remove all build/output artifacts, then require the requested script to
    # recreate them by running the complete pipeline.
    shutil.rmtree(os.path.join(PROJECT, "target"), ignore_errors=True)
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    run_checked([SCRIPT])
    assert os.path.isfile(BINARY), "run_operator.sh did not build the release binary"
    assert os.access(BINARY, os.X_OK), "The release binary is not executable"
    script_output = assert_manifest(expected)

    # Exercise the Rust artifact itself, rather than trusting output synthesized
    # by the shell script.
    os.unlink(OUTPUT)
    run_checked([BINARY])
    binary_output = assert_manifest(expected)
    assert binary_output == script_output, (
        "run_operator.sh output differs from the output of the built Rust tool"
    )


def test_run_operator_script_exists_and_executable():
    script_path = "/home/user/run_operator.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_configs_permissions():
    configs_dir = "/home/user/configs"
    assert os.path.isdir(configs_dir), f"Directory {configs_dir} does not exist."

    dir_stat = os.stat(configs_dir)
    assert stat.S_IMODE(dir_stat.st_mode) == 0o750, f"Permissions for {configs_dir} are not 0750. Got {oct(stat.S_IMODE(dir_stat.st_mode))}."

    for filename in os.listdir(configs_dir):
        filepath = os.path.join(configs_dir, filename)
        if os.path.isfile(filepath):
            file_stat = os.stat(filepath)
            assert stat.S_IMODE(file_stat.st_mode) == 0o640, f"Permissions for {filepath} are not 0640. Got {oct(stat.S_IMODE(file_stat.st_mode))}."


def test_manifests_yaml_exists():
    output_file = "/home/user/output/manifests.yaml"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist. Did the script run successfully?"


def test_manifests_yaml_size():
    output_file = "/home/user/output/manifests.yaml"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    file_size = os.path.getsize(output_file)
    threshold = 2000

    assert file_size <= threshold, f"Metric failed: File size of {output_file} is {file_size} bytes, which is greater than the threshold of {threshold} bytes. The Rust code loop might not be fixed correctly."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
