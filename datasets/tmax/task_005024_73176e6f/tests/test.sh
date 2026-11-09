#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def test_gitlab_ci_exists():
    """Test that the .gitlab-ci.yml file was generated."""
    assert os.path.exists("/home/user/.gitlab-ci.yml"), "/home/user/.gitlab-ci.yml was not generated."

def test_gitlab_ci_stages():
    """Test that the stages are correctly defined in .gitlab-ci.yml."""
    with open("/home/user/.gitlab-ci.yml", "r") as f:
        content = f.read()

    # Extract stages block
    stages_match = re.search(r'^stages:\s*\n((?:\s*-\s*stage_\d+\s*\n)+)', content, re.MULTILINE)
    assert stages_match is not None, "Could not find a valid 'stages:' array in the YAML."

    stages_block = stages_match.group(1)
    stages = re.findall(r'-\s*(stage_\d+)', stages_block)

    expected_stages = ["stage_0", "stage_1", "stage_2", "stage_3"]
    assert stages == expected_stages, f"Expected stages {expected_stages}, but got {stages}."

def test_gitlab_ci_jobs():
    """Test that each job is correctly defined with its stage and script."""
    with open("/home/user/.gitlab-ci.yml", "r") as f:
        content = f.read()

    expected_jobs = {
        "auth": "stage_0",
        "db": "stage_0",
        "user": "stage_1",
        "notification": "stage_2",
        "payment": "stage_2",
        "gateway": "stage_3",
    }

    for job, expected_stage in expected_jobs.items():
        # Find the job block, stopping at the next top-level key or end of file
        block_pattern = rf'^build_{job}:\s*\n(.*?)(?=^\S|\Z)'
        match = re.search(block_pattern, content, re.MULTILINE | re.DOTALL)
        assert match is not None, f"Job block 'build_{job}:' not found."

        block = match.group(1)

        # Check stage
        stage_match = re.search(r'^\s+stage:\s*(stage_\d+)', block, re.MULTILINE)
        assert stage_match is not None, f"'stage:' missing in 'build_{job}'."
        actual_stage = stage_match.group(1)
        assert actual_stage == expected_stage, f"Expected 'build_{job}' to be in {expected_stage}, got {actual_stage}."

        # Check script
        script_match = re.search(r'^\s+script:\s*\n\s*-\s*(.+)', block, re.MULTILINE)
        assert script_match is not None, f"'script:' array missing or malformed in 'build_{job}'."
        script_cmd = script_match.group(1).strip()

        # Allow optional quotes around the echo command, but strictly check the printed string
        expected_echo = f'echo "Building {job}"'
        assert expected_echo in script_cmd.replace("'", '"'), f"Expected script to contain '{expected_echo}' in 'build_{job}', got '{script_cmd}'."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_generator.py
import os
import random
import secrets
import shutil
import stat
import subprocess
import tempfile

import yaml

SCRIPT = "/home/user/ci_gen.py"
PROTO_DIR = "/home/user/protos"
OUTPUT = "/home/user/.gitlab-ci.yml"


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def construct_mapping(loader, node, deep=False):
    mapping = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise AssertionError(f"Duplicate YAML key: {key}")
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, construct_mapping
)


def layers_for(dependencies):
    memo = {}

    def layer(name):
        if name not in memo:
            memo[name] = 0 if not dependencies[name] else 1 + max(
                layer(dep) for dep in dependencies[name]
            )
        return memo[name]

    return {name: layer(name) for name in dependencies}


def write_fixture(dependencies):
    os.makedirs(PROTO_DIR, exist_ok=True)
    names = list(dependencies)
    random.SystemRandom().shuffle(names)
    for name in names:
        path = os.path.join(PROTO_DIR, name + ".proto")
        with open(path, "w", encoding="utf-8") as f:
            f.write('syntax = "proto3";\n')
            f.write(f"package {name};\n")
            for dep in dependencies[name]:
                f.write(f'import "{dep}.proto";\n')
            f.write(f"service {name}Service {{}}\n")


def verify_output(dependencies):
    assert os.path.isfile(OUTPUT), "ci_gen.py did not generate /home/user/.gitlab-ci.yml"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        data = yaml.load(f, Loader=UniqueKeyLoader)

    assert isinstance(data, dict), "Generated YAML must be a top-level mapping"
    layers = layers_for(dependencies)
    expected_stages = [f"stage_{i}" for i in range(max(layers.values()) + 1)]
    assert data.get("stages") == expected_stages, (
        f"Expected stages {expected_stages}, got {data.get('stages')}"
    )

    expected_keys = {"stages"} | {f"build_{name}" for name in dependencies}
    assert set(data) == expected_keys, (
        f"Expected exactly top-level keys {sorted(expected_keys)}, got {sorted(data)}"
    )

    for name, layer in layers.items():
        job_name = f"build_{name}"
        expected_job = {
            "stage": f"stage_{layer}",
            "script": [f'echo "Building {name}"'],
        }
        assert data[job_name] == expected_job, (
            f"Incorrect job block for {job_name}: {data[job_name]!r}"
        )


def make_case(topology):
    names = [f"svc_{secrets.token_hex(5)}" for _ in topology]
    return {
        names[index]: [names[dep_index] for dep_index in dep_indexes]
        for index, dep_indexes in enumerate(topology)
    }


def main():
    assert os.path.isfile(SCRIPT), "/home/user/ci_gen.py does not exist or is not a regular file"
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), "/home/user/ci_gen.py is not a regular file"

    backup_root = tempfile.mkdtemp(prefix="ci_gen_verify_")
    backup_protos = os.path.join(backup_root, "protos")
    had_output = os.path.exists(OUTPUT)
    output_bytes = None
    if had_output:
        with open(OUTPUT, "rb") as f:
            output_bytes = f.read()

    shutil.move(PROTO_DIR, backup_protos)
    try:
        cases = [
            # Two roots, branching dependencies, and a longest path of three edges.
            make_case([[], [], [0], [0, 1], [2], [2, 3], [4, 5, 1]]),
            # A different graph with an added service and a longest path of four edges.
            make_case([[], [0], [], [1, 2], [0, 2], [3, 4], [5], [2, 6]]),
        ]
        for dependencies in cases:
            if os.path.exists(PROTO_DIR):
                shutil.rmtree(PROTO_DIR)
            write_fixture(dependencies)
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            result = subprocess.run(
                ["python3", SCRIPT],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
            assert result.returncode == 0, (
                "ci_gen.py failed on a modified proto set.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            verify_output(dependencies)
    finally:
        if os.path.exists(PROTO_DIR):
            shutil.rmtree(PROTO_DIR)
        shutil.move(backup_protos, PROTO_DIR)
        if had_output:
            with open(OUTPUT, "wb") as f:
                f.write(output_bytes)
        elif os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        shutil.rmtree(backup_root, ignore_errors=True)


if __name__ == "__main__":
    main()
DYNAMIC_EOF

ok=1
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    ok=0
fi
if [ "$ok" -eq 1 ]; then
    if ! python3 /tmp/test_dynamic_generator.py 2>&1; then
        ok=0
    fi
fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
