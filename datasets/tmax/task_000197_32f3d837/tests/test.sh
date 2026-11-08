#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import uuid


def import_loader(module_name):
    mock_loader_path = "/home/user/app/mock_loader.py"
    assert os.path.isfile(mock_loader_path), f"File {mock_loader_path} is missing."
    spec = importlib.util.spec_from_file_location(module_name, mock_loader_path)
    mock_loader = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = mock_loader
    spec.loader.exec_module(mock_loader)
    return mock_loader


def test_build_success_log_exists():
    path = "/home/user/build_success.log"
    assert os.path.isfile(path), f"The success log {path} was not generated. Did you run the CI pipeline script?"


def test_build_success_log_content():
    path = "/home/user/build_success.log"
    assert os.path.isfile(path), f"The success log {path} was not generated."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "CI PASS", f"Expected 'CI PASS' in {path}, but got '{content}'."


def test_mock_loader_returns_sorted_routes():
    mock_loader = import_loader("mock_loader_original")
    routes = mock_loader.load_routing_mocks()
    assert len(routes) == 2, f"Expected exactly 2 routes to be loaded, got {len(routes)}."
    assert routes[0].get("path") == "/secure", "The first route loaded should be the secure route (/secure). Make sure the files are sorted."
    assert routes[1].get("path") == "/*", "The second route loaded should be the catch-all route (/*)."


def test_loader_sorts_additional_runtime_fixtures(monkeypatch):
    fixture_dir = "/home/user/app/fixtures"
    backup_dir = f"/home/user/app/fixtures.verifier-backup-{uuid.uuid4().hex}"
    token = uuid.uuid4().hex
    creation_order = [
        f"70_{token}.json",
        f"10_{token}.json",
        f"90_{token}.json",
        f"30_{token}.json",
        f"50_{token}.json",
        f"20_{token}.txt",
    ]
    records = {
        name: {"path": f"/{token}/{name}", "handler": f"handler-{i}"}
        for i, name in enumerate(creation_order)
        if name.endswith(".json")
    }

    assert os.path.isdir(fixture_dir), f"Fixture directory {fixture_dir} is missing."
    os.rename(fixture_dir, backup_dir)
    os.mkdir(fixture_dir)
    try:
        for name in creation_order:
            with open(os.path.join(fixture_dir, name), "w") as f:
                if name.endswith(".json"):
                    json.dump(records[name], f)
                else:
                    f.write("not a routing fixture\n")

        real_listdir = os.listdir
        fixture_norm = os.path.normpath(fixture_dir)

        def deliberately_unsorted_listdir(path):
            if os.path.normpath(os.fspath(path)) == fixture_norm:
                return list(creation_order)
            return real_listdir(path)

        monkeypatch.setattr(os, "listdir", deliberately_unsorted_listdir)
        loader = import_loader(f"mock_loader_dynamic_{token}")
        routes = loader.load_routing_mocks()
        expected = [records[name] for name in sorted(records)]
        assert routes == expected, (
            "load_routing_mocks() must load every JSON fixture in alphabetical "
            "filename order, including filenames introduced at verification time."
        )
    finally:
        monkeypatch.undo()
        shutil.rmtree(fixture_dir, ignore_errors=True)
        os.rename(backup_dir, fixture_dir)


def test_ci_pipeline_runs_and_generates_fresh_success_log():
    pipeline = "/home/user/app/ci_pipeline.sh"
    log_path = "/home/user/build_success.log"
    assert os.path.isfile(pipeline), f"CI pipeline script {pipeline} is missing."
    if os.path.exists(log_path):
        os.remove(log_path)

    result = subprocess.run(
        ["bash", pipeline],
        cwd="/home/user/app",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert result.returncode == 0, f"CI pipeline failed with output:\n{result.stdout}"
    assert os.path.isfile(log_path), "The CI pipeline did not generate /home/user/build_success.log."
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert content == "CI PASS", f"Expected a fresh CI PASS log, but got {content!r}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
