#!/bin/bash
mkdir -p /logs/verifier

# PyYAML is used to validate the generated workflow structurally.
if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    if ! pip3 install --quiet PyYAML >/dev/null 2>&1; then
        echo "0" > /logs/verifier/reward.txt
        exit 0
    fi
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import calendar
import datetime
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest
import yaml

PROJECT = "/home/user/data_project"
MIGRATE = os.path.join(PROJECT, "migrate.py")
SETUP_CI = os.path.join(PROJECT, "setup_ci.sh")


def test_migrate_script_exists():
    script_path = MIGRATE
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."


def test_setup_ci_script_exists_and_executable():
    script_path = SETUP_CI
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Path {script_path} is not a file."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_migrate_execution_and_output():
    raw_dir = os.path.join(PROJECT, "raw")
    processed_dir = os.path.join(PROJECT, "processed")

    # Ensure these outputs must be produced by this execution, rather than left
    # in place before verification.
    shutil.rmtree(processed_dir, ignore_errors=True)

    result = subprocess.run(
        ["python3", MIGRATE, raw_dir, processed_dir],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"migrate.py failed to run. Stderr: {result.stderr}"

    file1_path = os.path.join(processed_dir, "2021", "A001.json")
    file2_path = os.path.join(processed_dir, "2022", "B022.json")

    assert os.path.exists(file1_path), f"Expected output file {file1_path} not found."
    assert os.path.exists(file2_path), f"Expected output file {file2_path} not found."

    with open(file1_path, "r") as f:
        data1 = json.load(f)
    assert data1 == {"record_id": "A001", "first_name": "Alice", "last_name": "Smith", "year": 2021}, "Content of A001.json is incorrect."

    with open(file2_path, "r") as f:
        data2 = json.load(f)
    assert data2 == {"record_id": "B022", "first_name": "Bob", "last_name": "Jones", "year": 2022}, "Content of B022.json is incorrect."


def test_migrate_generalizes_to_runtime_generated_records_and_uses_utc():
    nonce = uuid.uuid4().hex[:12]
    records = [
        {
            "record_id": "R" + nonce + "A",
            "user_name": "Nora Alvarez",
            # Near a UTC year boundary, so local-time conversion in the TZ used
            # below would produce the wrong year.
            "epoch_time": calendar.timegm(datetime.datetime(2019, 1, 1, 1, 15).timetuple()),
            "expected_year": 2019,
        },
        {
            "record_id": "R" + nonce + "B",
            "user_name": "Quentin Berger",
            "epoch_time": calendar.timegm(datetime.datetime(2024, 7, 19, 18, 30).timetuple()),
            "expected_year": 2024,
        },
        {
            "record_id": "R" + nonce + "C",
            "user_name": "Uma Chen",
            "epoch_time": calendar.timegm(datetime.datetime(2031, 11, 3, 6, 0).timetuple()),
            "expected_year": 2031,
        },
    ]

    with tempfile.TemporaryDirectory() as root:
        input_dir = os.path.join(root, "unseen-input")
        output_dir = os.path.join(root, "unseen-output")
        os.makedirs(input_dir)

        for index, record in enumerate(records):
            source = {k: record[k] for k in ("record_id", "user_name", "epoch_time")}
            with open(os.path.join(input_dir, f"source-{index}-{nonce}.json"), "w") as f:
                json.dump(source, f)

        # This non-JSON file must not be treated as an input record.
        with open(os.path.join(input_dir, "ignore.txt"), "w") as f:
            f.write("not json")

        env = os.environ.copy()
        env["TZ"] = "Pacific/Honolulu"
        result = subprocess.run(
            ["python3", MIGRATE, input_dir, output_dir],
            capture_output=True,
            text=True,
            timeout=20,
            env=env,
        )
        assert result.returncode == 0, f"migrate.py failed on generated inputs: {result.stderr}"

        for record in records:
            first_name, last_name = record["user_name"].split()
            expected = {
                "record_id": record["record_id"],
                "first_name": first_name,
                "last_name": last_name,
                "year": record["expected_year"],
            }
            path = os.path.join(
                output_dir,
                str(record["expected_year"]),
                record["record_id"] + ".json",
            )
            assert os.path.isfile(path), f"Missing generated-record output: {path}"
            with open(path) as f:
                assert json.load(f) == expected


def test_migrate_requires_exactly_two_arguments():
    bad_invocations = [
        ["python3", MIGRATE],
        ["python3", MIGRATE, "/tmp/only-one"],
        ["python3", MIGRATE, "/tmp/in", "/tmp/out", "/tmp/extra"],
    ]
    for command in bad_invocations:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10)
        assert result.returncode != 0, f"Command unexpectedly accepted the wrong argument count: {command}"


def _is_migration_command(run_value):
    if not isinstance(run_value, str):
        return False

    # Examine individual shell command segments, allowing a preceding `cd` or
    # other ordinary workflow command while requiring actual migrate.py
    # execution with raw/ and processed/ as its two arguments.
    for segment in re.split(r"(?:&&|;|\n)", run_value):
        try:
            tokens = shlex.split(segment.strip())
        except ValueError:
            continue
        if not tokens:
            continue

        migrate_index = None
        direct = False
        for i, token in enumerate(tokens):
            if os.path.basename(token) == "migrate.py":
                migrate_index = i
                direct = i == 0
                break
        if migrate_index is None:
            continue

        invoked_by_python = (
            migrate_index > 0
            and os.path.basename(tokens[migrate_index - 1]) in {"python", "python3"}
        )
        if not (direct or invoked_by_python):
            continue

        args = tokens[migrate_index + 1:]
        if len(args) != 2:
            continue

        normalized = [arg.rstrip("/") for arg in args]
        if normalized[0] in {"raw", "./raw"} and normalized[1] in {"processed", "./processed"}:
            return True
    return False


def test_setup_ci_execution_and_output():
    result = subprocess.run([SETUP_CI], capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"setup_ci.sh failed to run. Stderr: {result.stderr}"

    pipeline_path = os.path.join(PROJECT, ".github", "workflows", "pipeline.yml")
    assert os.path.exists(pipeline_path), f"Pipeline file {pipeline_path} was not created."

    with open(pipeline_path, "r") as f:
        content = f.read()

    required_strings = [
        "process-data",
        "ubuntu-latest",
        "migrate.py",
        "cross-compile-tools",
        "make build ARCH=arm64",
    ]
    for req in required_strings:
        assert req in content, f"Pipeline file is missing required string: '{req}'"

    try:
        workflow = yaml.safe_load(content)
    except yaml.YAMLError as exc:
        pytest.fail(f"pipeline.yml is not valid YAML: {exc}")

    assert isinstance(workflow, dict), "Workflow YAML must contain a top-level mapping."
    jobs = workflow.get("jobs")
    assert isinstance(jobs, dict), "Workflow YAML must define a jobs mapping."
    job = jobs.get("process-data")
    assert isinstance(job, dict), "Workflow must define a job keyed 'process-data'."
    assert job.get("runs-on") == "ubuntu-latest", "process-data must run on ubuntu-latest."

    steps = job.get("steps")
    assert isinstance(steps, list), "process-data must contain a steps list."
    assert all(isinstance(step, dict) for step in steps), "Every workflow step must be a mapping."

    assert any(_is_migration_command(step.get("run")) for step in steps), (
        "A process-data step must execute migrate.py with raw/ and processed/ as its two arguments."
    )

    build_steps = [step for step in steps if step.get("name") == "cross-compile-tools"]
    assert build_steps, "Missing step named cross-compile-tools."
    assert any(
        "if" in step
        and step.get("if") not in (None, "", False)
        and isinstance(step.get("run"), str)
        and any(line.strip() == "make build ARCH=arm64" for line in step["run"].splitlines())
        for step in build_steps
    ), "cross-compile-tools must be conditional and run the exact arm64 build command."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
