#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import time
import subprocess
import socket
import re
import pytest
import requests
import numpy as np
import cv2

@pytest.fixture(scope="session", autouse=True)
def start_services():
    script_path = "/home/user/start_services.sh"
    assert os.path.isfile(script_path), f"Script {script_path} not found"

    # Ensure it's executable
    os.chmod(script_path, 0o755)

    # Start the services in a new process group
    proc = subprocess.Popen([script_path], preexec_fn=os.setsid)

    # Wait for services to initialize
    time.sleep(5)

    yield

    # Cleanup
    try:
        os.killpg(os.getpgid(proc.pid), 15)
    except Exception:
        pass

def get_truth_cov(sec):
    video_path = '/app/experiment_record.mp4'
    assert os.path.isfile(video_path), "Video file missing."

    cap = cv2.VideoCapture(video_path)
    cap.set(cv2.CAP_PROP_POS_FRAMES, sec * 30)
    ret, frame = cap.read()
    cap.release()

    assert ret, f"Could not read frame at sec {sec}"

    # Convert BGR (OpenCV default) to RGB as requested by the prompt
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

    pixels = frame_rgb.reshape(-1, 3)
    cov = np.cov(pixels.T, ddof=1)
    cov_flat = cov.flatten()
    return [round(float(c), 2) for c in cov_flat]

def get_truth_tokens(sec):
    annotations_path = '/app/annotations.txt'
    assert os.path.isfile(annotations_path), "Annotations file missing."

    with open(annotations_path, 'r') as f:
        lines = f.readlines()

    assert sec < len(lines), f"Requested sec {sec} out of bounds for annotations."
    line = lines[sec].lower()
    line = re.sub(r'[^a-z0-9 ]', '', line)
    return [w for w in line.split(' ') if w]

def test_http_service_rest_api():
    for sec in range(10):
        try:
            resp = requests.get(f"http://127.0.0.1:8080/data?sec={sec}", timeout=5)
        except requests.exceptions.RequestException as e:
            pytest.fail(f"HTTP GET request failed for sec {sec}: {e}")

        assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code} for sec {sec}"

        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"HTTP response is not valid JSON for sec {sec}. Response: {resp.text}")

        assert "sec" in data, "Missing 'sec' key in JSON response"
        assert data["sec"] == sec, f"Expected sec {sec}, got {data['sec']}"

        assert "tokens" in data, "Missing 'tokens' key in JSON response"
        expected_tokens = get_truth_tokens(sec)
        assert data["tokens"] == expected_tokens, f"Token mismatch at sec {sec}. Expected {expected_tokens}, got {data['tokens']}"

        assert "covariance" in data, "Missing 'covariance' key in JSON response"
        expected_cov = get_truth_cov(sec)
        actual_cov = data["covariance"]

        assert len(actual_cov) == 9, f"Expected 9 covariance values, got {len(actual_cov)}"
        np.testing.assert_allclose(actual_cov, expected_cov, atol=0.02, err_msg=f"Covariance mismatch at sec {sec} over HTTP")

def test_tcp_service_raw_socket():
    for sec in range(10):
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(5)
        try:
            s.connect(("127.0.0.1", 8081))
        except socket.error as e:
            pytest.fail(f"Failed to connect to TCP service on port 8081: {e}")

        try:
            s.sendall(f"{sec}\n".encode('utf-8'))

            response = b""
            while b"\n" not in response:
                chunk = s.recv(1024)
                if not chunk:
                    break
                response += chunk
        except socket.error as e:
            pytest.fail(f"TCP communication error at sec {sec}: {e}")
        finally:
            s.close()

        resp_str = response.decode('utf-8').strip()
        assert resp_str, f"Empty response from TCP service for sec {sec}"

        try:
            actual_cov = [float(x) for x in resp_str.split(',')]
        except ValueError:
            pytest.fail(f"Could not parse TCP response as comma-separated floats: {resp_str}")

        expected_cov = get_truth_cov(sec)

        assert len(actual_cov) == 9, f"Expected 9 covariance values, got {len(actual_cov)} in TCP response"
        np.testing.assert_allclose(actual_cov, expected_cov, atol=0.02, err_msg=f"Covariance mismatch at sec {sec} over TCP")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
