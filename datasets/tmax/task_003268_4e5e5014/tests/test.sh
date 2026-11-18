#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tarfile
import tempfile
import zipfile

import pytest

BACKUPS = Path("/home/user/backups")
EXTRACTED = Path("/home/user/extracted")
VERSIONS = ("v1", "v2", "v3")


def extract_backup(version, destination):
    destination.mkdir(parents=True, exist_ok=True)
    if version == "v2":
        with zipfile.ZipFile(BACKUPS / "v2.zip") as archive:
            archive.extractall(destination)
    else:
        with tarfile.open(BACKUPS / f"{version}.tar.gz", "r:gz") as archive:
            archive.extractall(destination)


def convert_ini_tree(root):
    for ini_path in sorted(root.rglob("*.ini")):
        parser = configparser.ConfigParser()
        with ini_path.open("r", encoding="utf-8") as source:
            parser.read_file(source)
        data = {
            section: {key: value for key, value in parser.items(section)}
            for section in parser.sections()
        }
        json_path = ini_path.with_suffix(".json")
        with json_path.open("w", encoding="utf-8") as output:
            json.dump(data, output, indent=2)
        ini_path.unlink()


def snapshot(root):
    result = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        if path.suffix == ".json":
            with path.open("r", encoding="utf-8") as source:
                result[relative] = ("json", json.load(source))
        else:
            result[relative] = ("bytes", path.read_bytes())
    return result


@pytest.fixture(scope="session", autouse=True)
def prepare_and_run_script():
    script = Path("/home/user/process.py")
    assert script.exists(), "/home/user/process.py does not exist"
    assert stat.S_ISREG(script.lstat().st_mode), "/home/user/process.py is not a regular file"

    expected = {}
    with tempfile.TemporaryDirectory() as temporary:
        reference_root = Path(temporary)
        for version in VERSIONS:
            version_root = reference_root / version
            extract_backup(version, version_root)
            convert_ini_tree(version_root)
            expected[version] = snapshot(version_root)

    if EXTRACTED.exists() or EXTRACTED.is_symlink():
        if EXTRACTED.is_symlink() or EXTRACTED.is_file():
            EXTRACTED.unlink()
        else:
            shutil.rmtree(EXTRACTED)
    EXTRACTED.mkdir(parents=True)
    for version in VERSIONS:
        extract_backup(version, EXTRACTED / version)

    try:
        completed = subprocess.run(
            ["python3", str(script)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("/home/user/process.py did not finish within 30 seconds")
    assert completed.returncode == 0, (
        "/home/user/process.py did not run cleanly.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    return expected


def expected_report(expected):
    v1 = expected["v1"]
    v3 = expected["v3"]
    return {
        "changed": sorted(path for path in v3 if path in v1 and v3[path] != v1[path]),
        "new": sorted(path for path in v3 if path not in v1),
    }


def test_process_converted_every_extracted_version(prepare_and_run_script):
    expected = prepare_and_run_script
    for version in VERSIONS:
        version_dir = EXTRACTED / version
        assert version_dir.is_dir(), f"Extracted directory {version_dir} does not exist"
        for root, _, files in os.walk(version_dir):
            for filename in files:
                assert not filename.endswith(".ini"), f"Found .ini file {filename} in {version_dir}"
        assert snapshot(version_dir) == expected[version], (
            f"Extracted contents for {version} do not exactly match the converted backup"
        )


def test_report_json_exists_and_correct(prepare_and_run_script):
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r", encoding="utf-8") as source:
        try:
            report = json.load(source)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert "changed" in report, "Report missing 'changed' key."
    assert "new" in report, "Report missing 'new' key."
    assert sorted(report["changed"]) == ["app/config.json", "system/network.json"], "Incorrect 'changed' files list."
    assert sorted(report["new"]) == ["app/db.json"], "Incorrect 'new' files list."
    assert report == expected_report(prepare_and_run_script), "report.json does not match the derived v1/v3 differences"


def test_extracted_directories_no_ini():
    extracted_base = "/home/user/extracted"
    for version in VERSIONS:
        version_dir = os.path.join(extracted_base, version)
        assert os.path.isdir(version_dir), f"Extracted directory {version_dir} does not exist"
        for root, _, files in os.walk(version_dir):
            for filename in files:
                assert not filename.endswith(".ini"), f"Found .ini file {filename} in {version_dir}"


def test_latest_config_archive(prepare_and_run_script):
    archive_path = "/home/user/latest_config.tar.gz"
    assert os.path.isfile(archive_path), f"Archive {archive_path} does not exist."

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(archive_path, "r:gz") as archive:
                archive.extractall(path=tmpdir)
        except tarfile.TarError:
            pytest.fail(f"Archive {archive_path} is not a valid tar.gz file.")

        tmp_root = Path(tmpdir)
        tmp_report = tmp_root / "report.json"
        assert tmp_report.is_file(), "report.json missing from root of latest_config.tar.gz"

        network_json = tmp_root / "system" / "network.json"
        assert network_json.is_file(), "system/network.json missing from archive"
        with network_json.open("r", encoding="utf-8") as source:
            net_data = json.load(source)
        assert net_data == {"interface": {"eth0": "static", "mtu": "9000"}}, "system/network.json content is incorrect"

        app_config = tmp_root / "app" / "config.json"
        assert app_config.is_file(), "app/config.json missing from archive"
        with app_config.open("r", encoding="utf-8") as source:
            app_data = json.load(source)
        assert app_data == {"feature_flag": True, "retries": 5}, "app/config.json content is incorrect"

        db_json = tmp_root / "app" / "db.json"
        assert db_json.is_file(), "app/db.json missing from archive"
        with db_json.open("r", encoding="utf-8") as source:
            db_data = json.load(source)
        assert db_data == {"mysql": {"host": "localhost", "port": "3306"}}, "app/db.json content is incorrect"

        for root, _, files in os.walk(tmpdir):
            for filename in files:
                assert not filename.endswith(".ini"), f"Found .ini file {filename} in archive"

        archived_report = json.loads(tmp_report.read_text(encoding="utf-8"))
        assert archived_report == expected_report(prepare_and_run_script), "Archived report.json is incorrect"

        archive_snapshot = snapshot(tmp_root)
        expected_files = dict(prepare_and_run_script["v3"])
        expected_files["report.json"] = ("json", expected_report(prepare_and_run_script))
        assert archive_snapshot == expected_files, (
            "Archive must contain exactly all converted v3 files plus report.json at its root"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
