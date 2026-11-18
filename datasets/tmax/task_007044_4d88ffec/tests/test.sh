#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import re
import secrets
import subprocess
import tarfile
import zipfile
from pathlib import Path

import pytest


def make_tgz(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        for name, data in entries.items():
            info = tarfile.TarInfo(name=name)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    return output.getvalue()


def make_zip(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    return output.getvalue()


def write_file(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def find_and_build_program():
    candidates = []
    excluded = {".cache", ".git", "backups", "go"}
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in excluded]
        go_files = [name for name in files if name.endswith(".go")]
        if not go_files:
            continue
        is_main = False
        for name in go_files:
            try:
                text = Path(root, name).read_text(errors="ignore")
            except OSError:
                continue
            if re.search(r"(?m)^\s*package\s+main\s*$", text):
                is_main = True
                break
        if is_main:
            candidates.append(root)

    assert candidates, "No Go source containing a package main was found under /home/user."
    candidates.sort(key=lambda p: (p.count(os.sep), p))
    binary = f"/tmp/config_tracker_{secrets.token_hex(8)}"
    failures = []

    for directory in candidates:
        for module_mode in (None, "off"):
            env = os.environ.copy()
            if module_mode is not None:
                env["GO111MODULE"] = module_mode
            result = subprocess.run(
                ["go", "build", "-o", binary, "."],
                cwd=directory,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=90,
            )
            if result.returncode == 0 and os.path.isfile(binary):
                return binary
            failures.append(f"{directory} (GO111MODULE={module_mode}):\n{result.stdout}")

    pytest.fail("No submitted Go main package could be built.\n" + "\n".join(failures))


def run_program(binary, config, output_path):
    Path("/home/user/config.json").write_text(json.dumps(config), encoding="utf-8")
    output = Path(output_path)
    if output.exists():
        output.unlink()
    result = subprocess.run(
        [binary],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Built Go program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert output.is_file(), f"The configured output file {output_path} was not created."
    try:
        return json.loads(output.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"The file {output_path} does not contain valid JSON: {exc}")


@pytest.fixture(scope="session")
def built_program():
    return find_and_build_program()


@pytest.fixture(scope="session")
def original_report(built_program, tmp_path_factory):
    root = tmp_path_factory.mktemp("original_archives")

    day1 = make_tgz({"app.conf": b"version=1.0.0\nsetting=abc\n"})
    inner = make_zip({"app.conf": b"version=1.1.0\n"})
    day2 = make_tgz({"inner.zip": inner})

    level4 = make_zip({"app.conf": b""})
    level3 = make_tgz({"level4.zip": level4})
    level2 = make_zip({"level3.tar.gz": level3})
    level1 = make_tgz({"level2.zip": level2})
    day3 = make_tgz({"level1.tar.gz": level1})

    paths = [root / "day1.tar.gz", root / "day2.tar.gz", root / "day3.tar.gz"]
    for path, data in zip(paths, (day1, day2, day3)):
        write_file(path, data)

    config = {
        "backups": [
            {"name": "day1", "path": str(paths[0])},
            {"name": "day2", "path": str(paths[1])},
            {"name": "day3", "path": str(paths[2])},
        ],
        "track_file": "app.conf",
        "max_depth": 3,
        "output": "/home/user/report.json",
    }
    return run_program(built_program, config, "/home/user/report.json")


def test_report_json_exists(original_report):
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The expected output file {report_path} was not created."


def test_report_json_content(original_report):
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The expected output file {report_path} was not created."

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_truth = {
        "day1": {"version": "1.0.0", "status": "ok"},
        "day2": {"version": "1.1.0", "status": "ok"},
        "day3": {"version": "", "status": "error_depth_exceeded"},
    }

    assert isinstance(report, dict), "The report should be a JSON object (dictionary)."

    for key, expected_val in expected_truth.items():
        assert key in report, f"Missing backup key '{key}' in the report."
        actual_val = report[key]
        assert isinstance(actual_val, dict), f"The value for '{key}' should be an object."
        assert actual_val.get("version") == expected_val["version"], f"Expected version '{expected_val['version']}' for '{key}', got '{actual_val.get('version')}'."
        assert actual_val.get("status") == expected_val["status"], f"Expected status '{expected_val['status']}' for '{key}', got '{actual_val.get('status')}'."

    for key in report.keys():
        assert key in expected_truth, f"Unexpected backup key '{key}' found in the report."


def test_runtime_generated_archives_and_configuration(built_program, tmp_path):
    token = secrets.token_hex(6)
    direct_name = f"direct_{token}"
    nested_name = f"nested_{token}"
    depth_two_name = f"depth_two_{token}"
    too_deep_name = f"too_deep_{token}"
    missing_name = f"missing_{token}"
    version_direct = f"7.{secrets.randbelow(900) + 100}.{secrets.randbelow(900) + 100}"
    version_nested = f"8.{secrets.randbelow(900) + 100}.{secrets.randbelow(900) + 100}"
    version_depth_two = f"9.{secrets.randbelow(900) + 100}.{secrets.randbelow(900) + 100}"

    direct = make_zip({"app.conf": f"setting=x\nversion={version_direct}\n".encode()})
    nested_inner = make_tgz({"app.conf": f"version={version_nested}\n".encode()})
    nested = make_zip({"folder/inner.tar.gz": nested_inner})
    depth_two_inner = make_tgz({"app.conf": f"version={version_depth_two}\n".encode()})
    depth_two_middle = make_zip({"next.tar.gz": depth_two_inner})
    depth_two = make_tgz({"middle.zip": depth_two_middle})
    too_deep_inner = make_tgz({"app.conf": b"version=should-not-be-read\n"})
    too_deep_level2 = make_zip({"level3.tar.gz": too_deep_inner})
    too_deep_level1 = make_tgz({"level2.zip": too_deep_level2})
    too_deep = make_zip({"level1.tar.gz": too_deep_level1})
    missing = make_tgz({"other.conf": b"version=irrelevant\n"})

    archive_data = [direct, nested, depth_two, too_deep, missing]
    archive_names = ["direct.zip", "nested.zip", "depth_two.tar.gz", "too_deep.zip", "missing.tar.gz"]
    paths = []
    for filename, data in zip(archive_names, archive_data):
        path = tmp_path / filename
        write_file(path, data)
        paths.append(path)

    output_path = f"/home/user/runtime_report_{token}.json"
    names = [direct_name, nested_name, depth_two_name, too_deep_name, missing_name]
    config = {
        "backups": [{"name": name, "path": str(path)} for name, path in zip(names, paths)],
        "track_file": "app.conf",
        "max_depth": 2,
        "output": output_path,
    }
    report = run_program(built_program, config, output_path)

    expected = {
        direct_name: {"version": version_direct, "status": "ok"},
        nested_name: {"version": version_nested, "status": "ok"},
        depth_two_name: {"version": version_depth_two, "status": "ok"},
        too_deep_name: {"version": "", "status": "error_depth_exceeded"},
        missing_name: {"version": "", "status": "error_not_found"},
    }
    assert report == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
