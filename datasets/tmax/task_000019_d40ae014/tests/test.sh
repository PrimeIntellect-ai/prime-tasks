#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile
import tempfile
import json
import pytest

ARCHIVE_PATH = "/home/user/final_archive.tar.gz"

EXPECTED_SERVER_DATA = [
    {"cpu": "80", "memory": "90", "disk": "50"},
    {"cpu": "60", "memory": "70", "disk": "80"},
]
EXPECTED_NETWORK_DATA = [
    {"rx": "1000", "tx": "500", "errors": "2"},
    {"rx": "2000", "tx": "800", "errors": "0"},
]


def normalize_csv_values(data):
    assert isinstance(data, list), "JSON document should contain an array of objects."
    normalized = []
    for row in data:
        assert isinstance(row, dict), "Each JSON array entry must be an object."
        normalized.append({key: str(value) for key, value in row.items()})
    return normalized


def test_archive_exists_and_valid():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive {ARCHIVE_PATH} does not exist."
    assert tarfile.is_tarfile(ARCHIVE_PATH), f"File {ARCHIVE_PATH} is not a valid tar archive."


def test_archive_contents():
    assert os.path.isfile(ARCHIVE_PATH), "Archive missing, cannot check contents."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        # Check logs
        syslog_path = os.path.join(tmpdir, "processed_data", "logs", "systemlog_a1.log")
        applog_path = os.path.join(tmpdir, "processed_data", "logs", "applog_b2.log")

        assert os.path.isfile(syslog_path), "Missing processed_data/logs/systemlog_a1.log in archive."
        assert os.path.isfile(applog_path), "Missing processed_data/logs/applog_b2.log in archive."

        # Check UTF-8 encoding and the complete converted content.
        with open(syslog_path, "rb") as f:
            content = f.read()
            try:
                text = content.decode("utf-8")
            except UnicodeDecodeError:
                pytest.fail("systemlog_a1.log is not valid UTF-8.")
            assert "Warning: Memory high" in text, "Content mismatch in systemlog_a1.log"
            assert text == "Warning: Memory high", "Complete content mismatch in systemlog_a1.log"

        with open(applog_path, "rb") as f:
            content = f.read()
            try:
                text = content.decode("utf-8")
            except UnicodeDecodeError:
                pytest.fail("applog_b2.log is not valid UTF-8.")
            assert "Error: Disk space low" in text, "Content mismatch in applog_b2.log"
            assert text == "Error: Disk space low", "Complete content mismatch in applog_b2.log"

        # Check JSON metrics
        server_json_path = os.path.join(tmpdir, "processed_data", "metrics", "serverstats_jan.json")
        network_json_path = os.path.join(tmpdir, "processed_data", "metrics", "networkstats_jan.json")

        assert os.path.isfile(server_json_path), "Missing processed_data/metrics/serverstats_jan.json in archive."
        assert os.path.isfile(network_json_path), "Missing processed_data/metrics/networkstats_jan.json in archive."

        with open(server_json_path, "r", encoding="utf-8") as f:
            try:
                server_data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("serverstats_jan.json is not valid JSON.")
            assert isinstance(server_data, list), "serverstats_jan.json should contain an array of objects."
            assert len(server_data) == 2, "serverstats_jan.json should have 2 entries."
            assert str(server_data[0].get("cpu")) == "80", "Incorrect data in serverstats_jan.json."
            assert str(server_data[1].get("disk")) == "80", "Incorrect data in serverstats_jan.json."
            assert normalize_csv_values(server_data) == EXPECTED_SERVER_DATA, \
                "serverstats_jan.json does not faithfully contain every CSV field and row."

        with open(network_json_path, "r", encoding="utf-8") as f:
            try:
                network_data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail("networkstats_jan.json is not valid JSON.")
            assert isinstance(network_data, list), "networkstats_jan.json should contain an array of objects."
            assert len(network_data) == 2, "networkstats_jan.json should have 2 entries."
            assert str(network_data[0].get("rx")) == "1000", "Incorrect data in networkstats_jan.json."
            assert str(network_data[1].get("errors")) == "0", "Incorrect data in networkstats_jan.json."
            assert normalize_csv_values(network_data) == EXPECTED_NETWORK_DATA, \
                "networkstats_jan.json does not faithfully contain every CSV field and row."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
