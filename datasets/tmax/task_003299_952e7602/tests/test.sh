#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import io
import os
import secrets
import socket
import subprocess
import pytest

HOST = "127.0.0.1"
PORT = 9090
AUTH = b"ETL_AUTH: VALID_STR_8472\n"
HEADER = ["Timestamp (ISO8601)", "Sensor_ID", "Anomaly_Score", "Cleaned_Notes"]


def legacy_output(cleaned_csv_line):
    result = subprocess.run(
        ["/app/sensor_processor"],
        input=cleaned_csv_line.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
        check=True,
    )
    rows = list(csv.reader(io.StringIO(result.stdout.decode("utf-8"))))
    return [row for row in rows if row]


def epoch_to_iso(value):
    dt = datetime.datetime.fromtimestamp(int(value), datetime.timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def transact(payload, auth=AUTH):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5.0)
    try:
        try:
            s.connect((HOST, PORT))
        except ConnectionRefusedError:
            pytest.fail("Server is not running on 127.0.0.1:9090")
        s.sendall(auth)
        if payload:
            s.sendall(payload.encode("utf-8"))
        s.shutdown(socket.SHUT_WR)
        response = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
        return response.decode("utf-8")
    finally:
        s.close()


def parse_response(response):
    assert "EOF_PIPELINE" in response, "Response did not end with EOF_PIPELINE"
    assert response.endswith("EOF_PIPELINE\n"), "Response must end with EOF_PIPELINE followed by a newline"
    body = response[:-len("EOF_PIPELINE\n")]
    rows = [row for row in csv.reader(io.StringIO(body), skipinitialspace=True) if row]
    if rows and [cell.strip() for cell in rows[0]] == HEADER:
        rows = rows[1:]
    return rows


def assert_long_rows(response, expected_legacy_row, note_parts):
    rows = parse_response(response)
    assert len(expected_legacy_row) == 4
    assert len(rows) == 3, "Each wide legacy anomaly must be reshaped into exactly three long rows"

    expected_timestamp = epoch_to_iso(expected_legacy_row[0])
    expected = {
        "Sensor1": float(expected_legacy_row[1]),
        "Sensor2": float(expected_legacy_row[2]),
        "Sensor3": float(expected_legacy_row[3]),
    }
    seen = set()
    for row in rows:
        assert len(row) == 4, "Long-format rows must have four columns"
        timestamp, sensor_id, score, notes = row
        assert timestamp.strip() == expected_timestamp
        sensor_id = sensor_id.strip()
        assert sensor_id in expected
        assert sensor_id not in seen
        seen.add(sensor_id)
        assert float(score) == pytest.approx(expected[sensor_id])
        assert "\n" not in notes and "\r" not in notes
        for part in note_parts:
            assert part in notes, "Cleaned_Notes did not preserve the submitted note"
    assert seen == set(expected)


def test_artifact_is_compiled_server_and_is_running():
    path = "/home/user/etl_server"
    assert os.path.isfile(path), "Missing /home/user/etl_server"
    assert os.access(path, os.X_OK), "/home/user/etl_server is not executable"
    with open(path, "rb") as f:
        submitted = f.read()
    assert submitted.startswith(b"\x7fELF"), "etl_server must be a compiled executable"
    with open("/app/sensor_processor", "rb") as f:
        assert submitted != f.read(), "etl_server cannot be the legacy processor itself"


def test_auth_failure():
    """Retain the original invalid-auth assertion."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect((HOST, PORT))
        s.sendall(b"ETL_AUTH: INVALID\n")
        data = s.recv(1024)
        assert data == b"", "Server should drop connection on invalid auth, but returned data."
    except ConnectionRefusedError:
        pytest.fail("Server is not running on 127.0.0.1:9090")
    finally:
        s.close()


def test_missing_auth_is_dropped():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(2.0)
    try:
        s.connect((HOST, PORT))
        s.sendall(b"2023-01-01T00:00:00Z,9.9,1,2,note\n")
        s.shutdown(socket.SHUT_WR)
        try:
            data = s.recv(1024)
        except ConnectionResetError:
            data = b""
        assert data == b""
    finally:
        s.close()


def test_pipeline_success_original_case():
    cleaned = '2023-10-12T10:00:00Z,9.9,1.1,2.2,"Note witha newline"\n'
    legacy_rows = legacy_output(cleaned)
    assert len(legacy_rows) == 1

    csv_data = (
        '2023-10-12T09:00:00Z,1.0,2.0,3.0,"Normal note"\n'
        '2023-10-12T10:00:00Z,9.9,1.1,2.2,"Note with\na newline"\n'
    )
    response = transact(csv_data)

    # Preserve the original verifier's assertions.
    assert "EOF_PIPELINE" in response, "Response did not end with EOF_PIPELINE"
    assert "Note with a newline" in response or "Note withnewline" in response or "Note with\ta newline" not in response, "Embedded newline was not properly handled."
    assert "Sensor1" in response, "Missing Sensor1 in long format."
    assert "Sensor2" in response, "Missing Sensor2 in long format."
    assert "Sensor3" in response, "Missing Sensor3 in long format."
    assert "2023-10-12T10:00:00Z" in response, "Missing or incorrect timestamp in output."

    assert_long_rows(response, legacy_rows[0], ["Note", "with", "a", "newline"])


def test_randomized_embedded_newline_and_derived_legacy_result():
    first = "N" + secrets.token_hex(12)
    second = "M" + secrets.token_hex(12)

    # Derive the expected anomaly and timestamp by executing the shipped legacy tool
    # on the correctly cleaned record rather than trusting hardcoded output strings.
    probe = '2001-01-01T00:00:00Z,9.9,4.2,5.3,"{}{}"\n'.format(first, second)
    legacy_rows = legacy_output(probe)
    assert len(legacy_rows) == 1
    aligned_timestamp = epoch_to_iso(legacy_rows[0][0])

    streamed = '{},9.9,4.2,5.3,"{}\n{}"\n'.format(aligned_timestamp, first, second)
    response = transact(streamed)
    assert_long_rows(response, legacy_rows[0], [first, second])


def test_no_anomaly_does_not_return_canned_sensor_rows():
    note = "Quiet" + secrets.token_hex(12)
    record = '2024-04-05T06:07:08Z,1.2,3.4,5.6,"{}"\n'.format(note)
    assert legacy_output(record) == []
    response = transact(record)
    rows = parse_response(response)
    assert rows == [], "Server returned anomaly rows when the legacy tool returned none"

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
