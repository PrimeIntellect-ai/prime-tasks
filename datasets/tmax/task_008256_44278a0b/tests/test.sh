#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import uuid

import pytest


def test_capacity_review_directory():
    assert os.path.isdir("/home/user/capacity_review"), "/home/user/capacity_review directory does not exist."


def test_report_json():
    report_path = "/home/user/capacity_review/report.json"
    assert os.path.isfile(report_path), f"{report_path} does not exist."

    with open(report_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} is not valid JSON.")

    assert "projects" in data, "JSON report missing 'projects' key."
    projects = data["projects"]

    # Expected order and sizes (based on initial setup)
    expected_projects = [
        {"name": "proj_gamma", "size_bytes": 100 * 1024 * 1024},
        {"name": "proj_alpha", "size_bytes": 50 * 1024 * 1024},
        {"name": "proj_beta", "size_bytes": 10 * 1024 * 1024},
        {"name": "proj_delta", "size_bytes": 5 * 1024 * 1024},
    ]

    assert len(projects) == len(expected_projects), f"Expected {len(expected_projects)} projects in report, found {len(projects)}."

    for i, expected in enumerate(expected_projects):
        assert projects[i]["name"] == expected["name"], f"Expected rank {i+1} to be {expected['name']}, got {projects[i].get('name')}."
        # Use >= expected size because directory itself might take a few bytes
        assert projects[i]["size_bytes"] >= expected["size_bytes"], f"Size for {expected['name']} is too small."


def test_symlinks():
    link1 = "/home/user/capacity_review/rank_1_proj_gamma"
    link2 = "/home/user/capacity_review/rank_2_proj_alpha"

    assert os.path.islink(link1), f"{link1} is not a symlink."
    assert os.path.islink(link2), f"{link2} is not a symlink."

    target1 = os.readlink(link1)
    target2 = os.readlink(link2)

    assert target1 == "../projects/proj_gamma", f"Symlink {link1} does not point to correct relative path. Got {target1}."
    assert target2 == "../projects/proj_alpha", f"Symlink {link2} does not point to correct relative path. Got {target2}."


def test_profile_env_var():
    profile_path = "/home/user/.profile"
    assert os.path.isfile(profile_path), f"{profile_path} does not exist."

    with open(profile_path, 'r') as f:
        content = f.read()

    expected_str = 'export CAPACITY_REVIEW_DIR="/home/user/capacity_review"'
    count = content.count(expected_str)

    assert count >= 1, f"{profile_path} does not contain the expected export statement."
    assert count == 1, f"{profile_path} contains the export statement multiple times (not idempotent)."


def test_pipeline_script():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_pipeline_log():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."


def file_totals_by_project():
    totals = {}
    projects_root = "/home/user/projects"
    for name in os.listdir(projects_root):
        project = os.path.join(projects_root, name)
        if not os.path.isdir(project):
            continue
        total = 0
        for root, _, files in os.walk(project):
            for filename in files:
                path = os.path.join(root, filename)
                if os.path.isfile(path):
                    total += os.path.getsize(path)
        totals[name] = total
    return totals


def run_pipeline():
    return subprocess.run(
        ["/home/user/pipeline.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def test_dynamic_analysis_idempotence_and_pipeline_redirection():
    analyzer = "/home/user/analyze_capacity.py"
    pipeline = "/home/user/pipeline.sh"
    assert os.path.isfile(analyzer), f"{analyzer} does not exist."
    assert os.path.isfile(pipeline), f"{pipeline} does not exist."

    analyzer_bytes = open(analyzer, "rb").read()
    analyzer_mode = os.stat(analyzer).st_mode
    project_name = "verification_" + uuid.uuid4().hex
    project_path = os.path.join("/home/user/projects", project_name)
    marker = "/tmp/capacity_probe_" + uuid.uuid4().hex
    stdout_token = "PROBE_STDOUT_" + uuid.uuid4().hex
    stderr_token = "PROBE_STDERR_" + uuid.uuid4().hex

    try:
        os.makedirs(os.path.join(project_path, "nested"))
        with open(os.path.join(project_path, "large.bin"), "wb") as f:
            f.truncate(110 * 1024 * 1024)
        with open(os.path.join(project_path, "nested", "small.bin"), "wb") as f:
            f.write(b"x" * 257)

        first = run_pipeline()
        assert first.returncode == 0, f"Pipeline failed on dynamic input: {first.stderr}"
        second = run_pipeline()
        assert second.returncode == 0, f"Pipeline was not idempotent: {second.stderr}"

        expected_totals = file_totals_by_project()
        with open("/home/user/capacity_review/report.json", "r") as f:
            data = json.load(f)

        assert set(data.keys()) == {"projects"}, "JSON report has an unexpected top-level format."
        reported = data["projects"]
        assert len(reported) == len(expected_totals), "Report does not contain every immediate project directory exactly once."
        assert all(set(item.keys()) == {"name", "size_bytes"} for item in reported), "Project entries do not match the required format."
        assert len({item["name"] for item in reported}) == len(reported), "Report contains duplicate projects."
        assert {item["name"] for item in reported} == set(expected_totals), "Report project names do not match the scanned directories."
        assert [item["size_bytes"] for item in reported] == sorted(
            [item["size_bytes"] for item in reported], reverse=True
        ), "Report is not sorted from largest to smallest."

        for item in reported:
            expected = expected_totals[item["name"]]
            assert isinstance(item["size_bytes"], int) and not isinstance(item["size_bytes"], bool)
            assert expected <= item["size_bytes"] <= expected + 1024 * 1024, (
                f"Reported size for {item['name']} is not derived from its files."
            )

        expected_ranked = sorted(expected_totals, key=expected_totals.get, reverse=True)
        assert expected_ranked[0] == project_name
        assert expected_ranked[1] == "proj_gamma"
        for rank, name in enumerate(expected_ranked[:2], 1):
            link = f"/home/user/capacity_review/rank_{rank}_{name}"
            assert os.path.islink(link), f"Dynamic top-consumer link {link} was not created."
            assert os.readlink(link) == f"../projects/{name}", f"{link} is not a correct relative symlink."

        expected_export = 'export CAPACITY_REVIEW_DIR="/home/user/capacity_review"'
        with open("/home/user/.profile", "r") as f:
            assert f.read().count(expected_export) == 1, "Repeated pipeline runs duplicated the profile export."

        probe = (
            "#!/usr/bin/env python3\n"
            "import pathlib, sys\n"
            f"pathlib.Path({marker!r}).write_text('executed')\n"
            f"print({stdout_token!r})\n"
            f"print({stderr_token!r}, file=sys.stderr)\n"
        )
        with open(analyzer, "w") as f:
            f.write(probe)
        os.chmod(analyzer, analyzer_mode)

        probed = run_pipeline()
        assert probed.returncode == 0, f"Pipeline failed to execute the analyzer probe: {probed.stderr}"
        assert os.path.isfile(marker), "pipeline.sh did not execute /home/user/analyze_capacity.py."
        with open("/home/user/pipeline.log", "r") as f:
            log = f.read()
        assert stdout_token in log, "Analyzer standard output was not redirected to pipeline.log."
        assert stderr_token in log, "Analyzer standard error was not redirected to pipeline.log."
    finally:
        with open(analyzer, "wb") as f:
            f.write(analyzer_bytes)
        os.chmod(analyzer, analyzer_mode)
        if os.path.exists(marker):
            os.unlink(marker)
        shutil.rmtree(project_path, ignore_errors=True)
        try:
            run_pipeline()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
