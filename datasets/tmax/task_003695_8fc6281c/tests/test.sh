#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import string
import subprocess

import pytest


def test_changepoint_json_exists():
    filepath = "/home/user/changepoint.json"
    assert os.path.isfile(filepath), f"Expected output file {filepath} does not exist."


def test_changepoint_json_content():
    filepath = "/home/user/changepoint.json"
    assert os.path.isfile(filepath), f"Expected output file {filepath} does not exist."

    with open(filepath, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {filepath} does not contain valid JSON.")

    expected_data = {
        "changepoint_date": "2023-10-08",
        "anomalous_value": 2500,
        "server_name": "WEB99"
    }

    assert data == expected_data, f"JSON content in {filepath} does not match the expected output. Got {data}"


def _valid_name(rng):
    letters = "".join(rng.choice(string.ascii_uppercase) for _ in range(3))
    digits = "".join(rng.choice(string.digits) for _ in range(2))
    return letters + digits


def _write_config(path, extension, server_name, connections, variant):
    if variant == 0:
        content = (
            f"serverName   :   {server_name}\n"
            f"MAXCONNECTIONS:\t{connections}\n"
            "OtherConfig: café\n"
        )
    elif variant == 1:
        content = (
            f"  SeRvErNaMe: {server_name}  \n"
            f" maxconnections : {connections} \n"
            "OtherConfig: legacy\n"
        )
    else:
        content = (
            f"ServerName: {server_name}\n"
            f"MaxConnections : {connections}\n"
            "OtherConfig: xyz\n"
        )

    encoding = {
        "utf8": "utf-8",
        "iso88591": "iso-8859-1",
        "utf16le": "utf-16le",
    }[extension]
    with open(path, "w", encoding=encoding) as f:
        f.write(content)


def test_tracker_executes_and_detects_derived_changepoints():
    tracker = "/home/user/tracker.go"
    assert os.path.isfile(tracker), f"Expected Go program {tracker} does not exist."

    rng = secrets.SystemRandom()
    configs_dir = "/home/user/configs"
    output = "/home/user/changepoint.json"
    extensions = ["utf8", "iso88591", "utf16le"]

    # Run independent cases so every supported encoding is exercised as the
    # encoding of the actual changepoint file.
    for case_number, anomaly_extension in enumerate(extensions):
        year = rng.randrange(2040, 2090)
        month = case_number + 1
        dates = [f"{year:04d}-{month:02d}-{day:02d}" for day in range(1, 6)]
        expected_name = _valid_name(rng)
        baseline_name = _valid_name(rng)
        later_name = _valid_name(rng)
        anomalous_value = rng.randrange(1101, 9000)
        invalid_spike = rng.randrange(9001, 15000)

        entries = [
            (dates[0], extensions[(case_number + 1) % 3], baseline_name, 100, 0),
            # This earlier spike must be ignored because the server name is invalid.
            (dates[1], extensions[(case_number + 2) % 3], "BADX99", invalid_spike, 1),
            (dates[2], anomaly_extension, expected_name, anomalous_value, 2),
            # A later valid spike must not replace the first valid changepoint.
            (dates[3], extensions[(case_number + 1) % 3], later_name, anomalous_value + 500, 0),
            (dates[4], extensions[(case_number + 2) % 3], baseline_name, 100, 1),
        ]

        shutil.rmtree(configs_dir, ignore_errors=True)
        os.makedirs(configs_dir)
        random.SystemRandom().shuffle(entries)
        for date, extension, name, value, variant in entries:
            filename = os.path.join(configs_dir, f"config_{date}.{extension}")
            _write_config(filename, extension, name, value, variant)

        if os.path.exists(output):
            os.remove(output)

        result = subprocess.run(
            ["go", "run", tracker],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, (
            f"Running {tracker} failed with exit code {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(output), f"Running {tracker} did not create {output}."

        with open(output, "r", encoding="utf-8") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f"File {output} does not contain valid JSON after execution: {exc}")

        expected = {
            "changepoint_date": dates[2],
            "anomalous_value": anomalous_value,
            "server_name": expected_name,
        }
        assert actual == expected, f"Tracker produced {actual}; expected {expected}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
