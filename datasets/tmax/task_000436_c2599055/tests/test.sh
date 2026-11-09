#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import tarfile
import zipfile
import csv
import xml.etree.ElementTree as ET
import io
import pytest

def get_expected_data():
    master_path = "/home/user/config_backups.ccp"
    expected = {}

    assert os.path.exists(master_path), f"Master archive {master_path} is missing."

    with tarfile.open(master_path, "r:gz") as tf:
        index_file = tf.extractfile("index.xml")
        assert index_file is not None, "index.xml missing in master archive."

        tree = ET.parse(index_file)
        root = tree.getroot()

        for version in root.findall("version"):
            v_id = version.get("id")
            v_file = version.get("file")

            nested_file = tf.extractfile(v_file)
            assert nested_file is not None, f"{v_file} missing in master archive."
            nested_bytes = io.BytesIO(nested_file.read())

            max_conn = None
            cache_port = None

            if v_file.endswith(".zip"):
                with zipfile.ZipFile(nested_bytes) as zf:
                    with zf.open("app_config.json") as f:
                        config = json.load(f)
                        max_conn = config["database"]["max_connections"]

                    with zf.open("services.csv") as f:
                        reader = csv.DictReader(io.TextIOWrapper(f, 'utf-8'))
                        for row in reader:
                            if row["service_name"] == "cache_service":
                                cache_port = int(row["port"])
                                break
            elif v_file.endswith(".tar.gz"):
                with tarfile.open(fileobj=nested_bytes, mode="r:gz") as ntf:
                    f_json = ntf.extractfile("app_config.json")
                    config = json.load(f_json)
                    max_conn = config["database"]["max_connections"]

                    f_csv = ntf.extractfile("services.csv")
                    reader = csv.DictReader(io.TextIOWrapper(f_csv, 'utf-8'))
                    for row in reader:
                        if row["service_name"] == "cache_service":
                            cache_port = int(row["port"])
                            break

            expected[v_id] = {
                "max_connections": max_conn,
                "cache_port": cache_port
            }

    return expected

def test_change_report_exists_and_correct():
    report_path = "/home/user/change_report.json"
    assert os.path.exists(report_path), f"Expected report file not found at {report_path}"

    with open(report_path, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON")

    expected_data = get_expected_data()

    assert actual_data == expected_data, f"Report data does not match expected.\nActual: {actual_data}\nExpected: {expected_data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
