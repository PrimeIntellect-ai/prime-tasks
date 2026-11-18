#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import socket
import subprocess

import cv2
import numpy as np


def send_tcp_request(host, port, message):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        s.connect((host, port))
        s.sendall(message.encode('utf-8'))
        response = b""
        while True:
            try:
                chunk = s.recv(4096)
                if not chunk:
                    break
                response += chunk
            except socket.timeout:
                break
        return response.decode('utf-8')


def decode_raw_values(video_path):
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Unable to open telemetry video: {video_path}"
    values = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame.ndim == 3:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        else:
            gray = frame
        normalized_mean = float(gray.mean()) / 255.0
        values.append(int(math.floor(normalized_mean * 1000.0 + 0.5)))
    cap.release()
    assert values, f"No frames decoded from {video_path}"
    return values


def expected_cleaned_values():
    # Recreate and decode an independent copy so expectations include pixel
    # quantization and MP4 compression rather than using pre-encoding values.
    source_values = [200, 250, 300, 2, 400, 450, 500, 5, 600, 650,
                     700, 750, 800, 8, 900, 950, 850, 750, 650, 550]
    reference_path = "/tmp/verifier_reference_telemetry.mp4"
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(reference_path, fourcc, 1.0, (100, 100), isColor=False)
    assert out.isOpened(), "Unable to create verifier reference video"
    for value in source_values:
        pixel_value = int((value / 1000.0) * 255.0)
        out.write(np.full((100, 100), pixel_value, dtype=np.uint8))
    out.release()

    reference_raw = decode_raw_values(reference_path)
    artifact_raw = decode_raw_values('/app/telemetry.mp4')
    assert artifact_raw == reference_raw, "The supplied telemetry video was modified"

    valid_indices = [i for i, value in enumerate(artifact_raw) if value >= 10]
    assert valid_indices, "Telemetry contains no valid sensor readings"
    cleaned = list(artifact_raw)
    for i, value in enumerate(artifact_raw):
        if value >= 10:
            continue
        preceding = next((artifact_raw[j] for j in range(i - 1, -1, -1)
                          if artifact_raw[j] >= 10), None)
        succeeding = next((artifact_raw[j] for j in range(i + 1, len(artifact_raw))
                           if artifact_raw[j] >= 10), None)
        if preceding is None:
            cleaned[i] = succeeding
        elif succeeding is None:
            cleaned[i] = preceding
        else:
            cleaned[i] = int(math.floor((preceding + succeeding) / 2.0 + 0.5))
    return cleaned


EXPECTED_VALUES = expected_cleaned_values()


def test_cleaned_csv():
    """Test that the cleaned CSV file exists and contains the correctly imputed data."""
    csv_path = "/home/user/cleaned_telemetry.csv"
    assert os.path.isfile(csv_path), f"Missing cleaned CSV file: {csv_path}"

    with open(csv_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    for i, val in enumerate(EXPECTED_VALUES):
        expected_line = f"{i+1},{val}"
        assert expected_line in lines, f"Expected line '{expected_line}' not found in {csv_path}"


def test_tcp_server_schema():
    """Test that the TCP server correctly responds to the SCHEMA command."""
    response = send_tcp_request('127.0.0.1', 9090, "SCHEMA\n")
    expected = "frame_number:int,sensor_value:int\n"
    assert response == expected, f"Unexpected SCHEMA response. Expected {repr(expected)}, got {repr(response)}"


def test_tcp_server_data():
    """Test that the TCP server correctly responds to DATA commands with imputed values."""
    for frame in (4, 8, 14, 1, 20):
        expected_val = EXPECTED_VALUES[frame - 1]
        response = send_tcp_request('127.0.0.1', 9090, f"DATA {frame}\n")
        expected = f"{expected_val}\n"
        assert response == expected, f"Unexpected DATA {frame} response. Expected {repr(expected)}, got {repr(response)}"


def test_tcp_server_stats():
    """Test that the TCP server correctly responds to the instructed bootstrap statistics."""
    data = " ".join(str(value) for value in EXPECTED_VALUES)
    awk_script = f'''
BEGIN {{
    srand(42)
    split("{data}", data, " ")
    n = length(data)
    for(i=1; i<=10000; i++) {{
        sum = 0
        for(j=1; j<=n; j++) {{
            idx = int(rand() * n) + 1
            sum += data[idx]
        }}
        means[i] = sum / n
    }}
    asort(means)
    total = 0
    for(i=1; i<=10000; i++) total += means[i]
    mean = total / 10000
    lower = means[250]
    upper = means[9750]
    printf "mean:%.2f,lower:%.2f,upper:%.2f\\n", mean, lower, upper
}}
'''
    script_path = '/tmp/truth_bootstrap.awk'
    with open(script_path, 'w') as f:
        f.write(awk_script)

    result = subprocess.run(['gawk', '-f', script_path], capture_output=True, text=True)
    expected_stats = result.stdout

    response = send_tcp_request('127.0.0.1', 9090, "STATS\n")
    assert response == expected_stats, f"Unexpected STATS response. Expected {repr(expected_stats)}, got {repr(response)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
