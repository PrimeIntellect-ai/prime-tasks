#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import secrets
import shutil
import subprocess
import tarfile

DATA_DIR = "/home/user/data"
ARCHIVE_PATH = "/home/user/dataset_backup.tar.gz"

EXPECTED_CSVS = {
    "dataset_A.csv": "id,val\n1,100\n2,150",
    "dataset_B.csv": "id,val\n3,200\n4,250",
    "dataset_C.csv": "id,val\n5,300",
}


def normalize_csv_content(content: str) -> str:
    lines = [line.strip() for line in content.strip().splitlines() if line.strip()]
    return "\n".join(lines)


def assert_archive(expected_csvs):
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} is missing."

    expected_archive_files = [f"data/{name}" for name in expected_csvs]
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        members = tar.getnames()

        for expected_file in expected_archive_files:
            assert members.count(expected_file) == 1, \
                f"Archive must contain exactly one {expected_file}."

        extras = [
            name for name in members
            if name not in expected_archive_files and name.rstrip("/") != "data"
        ]
        assert not extras, f"Archive contains unexpected members: {extras}"
        data_entries = [name for name in members if name.rstrip("/") == "data"]
        assert len(data_entries) <= 1, "Archive contains duplicate data directory entries."
        if data_entries:
            assert tar.getmember(data_entries[0]).isdir(), \
                "The archive's data entry is not a directory."

        for filename, expected_content in expected_csvs.items():
            member_name = f"data/{filename}"
            member = tar.getmember(member_name)
            assert member.isfile(), f"Archive member {member_name} is not a file."

            f = tar.extractfile(member)
            assert f is not None, f"Could not extract {member_name} from archive."
            content = f.read().decode("utf-8")
            assert normalize_csv_content(content) == normalize_csv_content(expected_content), \
                f"Content of {member_name} inside archive does not match expected data."


def test_csv_files_exist_and_content_correct():
    for filename, expected_content in EXPECTED_CSVS.items():
        filepath = os.path.join(DATA_DIR, filename)
        assert os.path.isfile(filepath), f"Expected CSV file {filepath} is missing."

        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()

        assert normalize_csv_content(content) == normalize_csv_content(expected_content), \
            f"Content of {filepath} does not match the expected CSV data."


def test_no_json_files_remain():
    json_files = glob.glob(os.path.join(DATA_DIR, "*.json"))
    assert len(json_files) == 0, f"JSON files were not deleted: {json_files}"


def test_only_normalized_csv_files_remain():
    actual = set(os.listdir(DATA_DIR))
    expected = set(EXPECTED_CSVS)
    assert actual == expected, \
        f"Data directory must contain only normalized CSVs; found {sorted(actual)}"
    for filename in actual:
        assert os.path.isfile(os.path.join(DATA_DIR, filename)), \
            f"Unexpected non-file entry in data directory: {filename}"


def test_archive_exists_and_contents():
    assert_archive(EXPECTED_CSVS)


def find_python_scripts():
    candidates = []
    search_files = []
    for root, _, files in os.walk("/home/user"):
        for filename in files:
            search_files.append(os.path.join(root, filename))
    search_files.extend(glob.glob("/tmp/*"))

    for path in search_files:
        if path == "/tmp/test_final_state.py" or not os.path.isfile(path):
            continue
        is_python = path.endswith(".py")
        if not is_python:
            try:
                with open(path, "rb") as f:
                    is_python = b"python" in f.readline(256).lower() and f.readline(0) == b""
            except OSError:
                continue
        if is_python:
            candidates.append(path)
    return sorted(set(candidates))


def install_dynamic_fixture(ids, values):
    shutil.rmtree(DATA_DIR, ignore_errors=True)
    os.makedirs(DATA_DIR, exist_ok=True)
    try:
        os.remove(ARCHIVE_PATH)
    except FileNotFoundError:
        pass

    fixtures = [
        (f"raw_exp_{ids[0]}.json", [{"id": 11, "val": values[0]}, {"id": 12, "val": values[1]}]),
        (f"results_{ids[1]}_exp.json", [{"id": 21, "val": values[2]}]),
    ]
    for filename, records in fixtures:
        with open(os.path.join(DATA_DIR, filename), "w", encoding="utf-8") as f:
            json.dump(records, f)

    with open(os.path.join(DATA_DIR, f"exp_{ids[2]}_raw.csv"), "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["id", "val"])
        writer.writerow([31, values[3]])
        writer.writerow([32, values[4]])


def test_z_python_script_performs_the_work_on_derived_inputs():
    candidates = find_python_scripts()
    assert candidates, "No Python script implementing the requested operation was found."

    ids = secrets.SystemRandom().sample(list("DEFGHIJKLMNOPQRSTUVWXYZ"), 3)
    values = [secrets.randbelow(800000) + 10000 for _ in range(5)]
    expected = {
        f"dataset_{ids[0]}.csv": f"id,val\n11,{values[0]}\n12,{values[1]}",
        f"dataset_{ids[1]}.csv": f"id,val\n21,{values[2]}",
        f"dataset_{ids[2]}.csv": f"id,val\n31,{values[3]}\n32,{values[4]}",
    }

    failures = []
    for script in candidates:
        if not os.path.isfile(script):
            continue
        install_dynamic_fixture(ids, values)
        try:
            result = subprocess.run(
                ["python3", script], cwd="/home/user", text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
            )
            assert result.returncode == 0, result.stdout
            assert set(os.listdir(DATA_DIR)) == set(expected), \
                f"Unexpected data directory entries: {os.listdir(DATA_DIR)}"
            for filename, expected_content in expected.items():
                path = os.path.join(DATA_DIR, filename)
                assert os.path.isfile(path), f"Missing generated file {path}"
                with open(path, encoding="utf-8") as f:
                    assert normalize_csv_content(f.read()) == normalize_csv_content(expected_content)
            assert_archive(expected)
            return
        except Exception as exc:
            failures.append(f"{script}: {exc}")

    raise AssertionError("No submitted Python script completed the task on derived inputs:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
