#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

SCORER_REAL="/app/.legacy_scorer.verifier-real"
MARKER="/tmp/legacy_scorer_invoked.$$.log"
PREEXISTING=0

cleanup() {
    if [ -e "$SCORER_REAL" ]; then
        rm -f /app/legacy_scorer
        mv "$SCORER_REAL" /app/legacy_scorer
    fi
    rm -f "$MARKER"
}
trap cleanup EXIT

for exe in /proc/[0-9]*/exe; do
    target="$(readlink "$exe" 2>/dev/null || true)"
    if [ "$target" = "/app/legacy_scorer" ]; then
        PREEXISTING=1
        break
    fi
done

rm -f "$MARKER"
mv /app/legacy_scorer "$SCORER_REAL"
cat > /app/legacy_scorer <<EOF
#!/bin/sh
printf 'invoked\n' >> '$MARKER'
exec '$SCORER_REAL' "\$@"
EOF
chmod 755 /app/legacy_scorer

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import socket
import stat
import time

import pytest
import requests


def wait_for_port(port, host='127.0.0.1', timeout=5.0):
    start_time = time.time()
    while time.time() - start_time < timeout:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            if sock.connect_ex((host, port)) == 0:
                return True
        time.sleep(0.1)
    return False


@pytest.fixture(scope="module")
def server_url():
    path = "/home/user/etl_server"
    st = os.stat(path)
    assert stat.S_ISREG(st.st_mode), "etl_server is not a regular file"
    assert os.access(path, os.X_OK), "etl_server is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "etl_server is not a compiled ELF binary"
    assert wait_for_port(9000), "Server is not listening on port 9000"
    return "http://127.0.0.1:9000/process"


def assert_response(server_url, csv_data, expected_output):
    response = requests.post(server_url, data=csv_data, timeout=5)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert "text/plain" in response.headers.get("Content-Type", ""), "Expected Content-Type: text/plain"
    assert response.text == expected_output, (
        f"Output mismatch.\nExpected:\n{expected_output}\nGot:\n{response.text}"
    )


def test_process_normal_csv(server_url):
    csv_data = (
        "timestamp,sensor1,sensor2,sensor3\n"
        "2023-01-01T00:00:00Z,10.0,60.0,20.0\n"
        "2023-01-01T00:01:00Z,80.0,10.0,90.0\n"
    )
    expected_output = (
        "ALARM: Sensor sensor2 at 2023-01-01T00:00:00Z triggered an anomaly!\n"
        "ALARM: Sensor sensor1 at 2023-01-01T00:01:00Z triggered an anomaly!\n"
        "ALARM: Sensor sensor3 at 2023-01-01T00:01:00Z triggered an anomaly!\n"
    )

    response = requests.post(server_url, data=csv_data)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert "text/plain" in response.headers.get("Content-Type", ""), "Expected Content-Type: text/plain"
    assert response.text == expected_output, f"Output mismatch.\nExpected:\n{expected_output}\nGot:\n{response.text}"


def test_process_csv_with_embedded_newlines(server_url):
    csv_data = (
        "timestamp,sensor1,sensor2,sensor3\n"
        "2023-01-01T00:02:00Z,10.0,\"60.0\nnew\",20.0\n"
        "2023-01-01T00:03:00Z,80.0,10.0,90.0\n"
        "2023-01-01T00:04:00Z,90.0,\"40.0\",10.0\n"
    )
    expected_output = (
        "ALARM: Sensor sensor1 at 2023-01-01T00:03:00Z triggered an anomaly!\n"
        "ALARM: Sensor sensor3 at 2023-01-01T00:03:00Z triggered an anomaly!\n"
        "ALARM: Sensor sensor1 at 2023-01-01T00:04:00Z triggered an anomaly!\n"
    )

    response = requests.post(server_url, data=csv_data)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
    assert response.text == expected_output, f"Output mismatch for embedded newlines.\nExpected:\n{expected_output}\nGot:\n{response.text}"


def csv_number(value, quote):
    text = f"{value:.3f}"
    return f'"{text}"' if quote else text


def test_randomized_csv_reshaping_and_cleaning(server_url):
    rng = random.SystemRandom()
    sensors = ("sensor1", "sensor2", "sensor3")

    for request_index in range(5):
        nonce = secrets.token_hex(10)
        physical_lines = ["timestamp,sensor1,sensor2,sensor3\n"]
        expected = []
        row_count = rng.randint(4, 9)
        corrupt_position = rng.randrange(row_count)

        for row_index in range(row_count):
            timestamp = f"rnd-{nonce}-{request_index}-{row_index}"
            values = [rng.uniform(-125.0, 49.25) if rng.randrange(2) else rng.uniform(50.75, 175.0) for _ in range(3)]

            if row_index == corrupt_position:
                corrupt_sensor = rng.randrange(3)
                fields = [csv_number(value, rng.randrange(2) == 0) for value in values]
                fields[corrupt_sensor] = f'"{values[corrupt_sensor]:.3f}\ncorrupt-{secrets.token_hex(4)}"'
                physical_lines.append(timestamp + "," + ",".join(fields) + "\n")
                continue

            fields = [csv_number(value, rng.randrange(2) == 0) for value in values]
            physical_lines.append(timestamp + "," + ",".join(fields) + "\n")
            for sensor, value in zip(sensors, values):
                if value > 50.0:
                    expected.append(
                        f"ALARM: Sensor {sensor} at {timestamp} triggered an anomaly!\n"
                    )

        assert_response(server_url, "".join(physical_lines), "".join(expected))


def test_legacy_scorer_was_invoked():
    marker = os.environ["SCORER_MARKER"]
    preexisting = os.environ.get("SCORER_PREEXISTING") == "1"
    assert preexisting or (os.path.exists(marker) and os.path.getsize(marker) > 0), (
        "The service did not invoke /app/legacy_scorer"
    )
TEST_EOF

if SCORER_MARKER="$MARKER" SCORER_PREEXISTING="$PREEXISTING" \
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
fi
