#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import io
import os
import tarfile

BACKUPS = "/home/user/backups"
EXTRACTED = "/home/user/extracted"
SAFE_CONFIGS = "/home/user/safe_configs"
REPORT = "/home/user/recovery_report.txt"


def source_artifacts():
    parts = sorted(glob.glob(os.path.join(BACKUPS, "split_archive.tar.gz.*")))
    assert parts, "No split archive parts were found."
    archive_data = b"".join(open(path, "rb").read() for path in parts)

    with tarfile.open(fileobj=io.BytesIO(archive_data), mode="r:gz") as outer:
        regular = {m.name: outer.extractfile(m).read() for m in outer.getmembers() if m.isfile()}

    assert "configs.tar" in regular, "Reassembled archive does not contain configs.tar."
    assert "rules.txt" in regular, "Reassembled archive does not contain rules.txt."

    configs = {}
    with tarfile.open(fileobj=io.BytesIO(regular["configs.tar"]), mode="r:") as inner:
        for member in inner.getmembers():
            if member.isfile() and member.name.endswith(".conf"):
                old_basename = os.path.basename(member.name)
                assert old_basename.startswith("old_")
                new_name = old_basename[len("old_"):-len(".conf")] + ".ini"
                assert new_name not in configs, f"Duplicate flattened filename: {new_name}"
                configs[new_name] = inner.extractfile(member).read()

    rules = []
    for line in regular["rules.txt"].decode("utf-8").splitlines():
        if line.strip():
            filename, key = line.split(":", 1)
            rules.append((filename, key))

    expected_report = []
    for filename, key in rules:
        values = {}
        for line in configs[filename].decode("utf-8").splitlines():
            if "=" in line:
                config_key, value = line.split("=", 1)
                values[config_key] = value
        expected_report.append(f"{filename}:{values[key]}")

    return regular, configs, sorted(expected_report)


def test_recovery_report_exists():
    report_path = "/home/user/recovery_report.txt"
    assert os.path.exists(report_path), f"{report_path} does not exist."
    assert os.path.isfile(report_path), f"{report_path} is not a file."


def test_recovery_report_contents():
    with open(REPORT, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected = [
        "db.ini:192.168.1.100",
        "web.ini:4"
    ]
    expected_sorted = sorted(expected)
    assert lines == expected_sorted, f"Report content mismatch. Expected {expected_sorted}, got {lines}"


def test_safe_configs_directory_exists():
    assert os.path.isdir(SAFE_CONFIGS), f"{SAFE_CONFIGS} directory is missing."


def test_renamed_ini_files_exist():
    db_ini_path = os.path.join(SAFE_CONFIGS, "db.ini")
    web_ini_path = os.path.join(SAFE_CONFIGS, "web.ini")
    assert os.path.isfile(db_ini_path), f"{db_ini_path} is missing."
    assert os.path.isfile(web_ini_path), f"{web_ini_path} is missing."


def test_outer_archive_was_extracted_correctly():
    regular, _, _ = source_artifacts()
    assert os.path.isdir(EXTRACTED), f"{EXTRACTED} directory is missing."
    for name in ("configs.tar", "rules.txt"):
        path = os.path.join(EXTRACTED, name)
        assert os.path.isfile(path), f"{path} is missing."
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == regular[name], f"{path} does not match the file in the reassembled archive."


def test_configs_are_flattened_renamed_and_preserved():
    _, expected_configs, _ = source_artifacts()
    entries = os.listdir(SAFE_CONFIGS)
    assert sorted(entries) == sorted(expected_configs), (
        f"safe_configs must contain exactly the flattened, renamed configuration files; got {entries}"
    )
    for filename, expected_data in expected_configs.items():
        path = os.path.join(SAFE_CONFIGS, filename)
        assert os.path.isfile(path), f"{path} is not a regular file."
        with open(path, "rb") as f:
            actual_data = f.read()
        assert actual_data == expected_data, f"Recovered contents of {filename} are incorrect."


def test_report_is_derived_from_recovered_rules_and_configs():
    _, _, expected_report = source_artifacts()
    with open(REPORT, "r", encoding="utf-8") as f:
        actual = [line.rstrip("\n") for line in f]
    assert actual == expected_report, f"Expected report {expected_report}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
