#!/bin/bash
mkdir -p /logs/verifier

DECODER=/app/sensor_decode
REAL_DECODER=/app/sensor_decode.verifier-real
MARKER="/tmp/sensor_decode_calls.$$"

# Interpose a transparent wrapper so the tests verify that submitted services
# actually invoke the supplied decoder for the unpredictable payloads.
if [ ! -f "$DECODER" ] || [ ! -x "$DECODER" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
if ! mv "$DECODER" "$REAL_DECODER"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
: > "$MARKER"
chmod 666 "$MARKER"
cat > "$DECODER" <<WRAPPER_EOF
#!/bin/bash
printf '%s\n' "\$1" >> "$MARKER"
exec "$REAL_DECODER" "\$@"
WRAPPER_EOF
chmod 755 "$DECODER"
export SENSOR_MARKER="$MARKER"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import collections
import csv
import math
import os
import random
import secrets
from datetime import datetime, timezone

import requests

URL = "http://127.0.0.1:9042/api/v1/telemetry"
AUTH_HEADER = {"Authorization": "Bearer sec-iot-pipeline-8821"}
EXPECTED_KEYS = {"bucket_start_time", "mean_value", "rolling_avg", "is_anomaly"}
SENT_PAYLOADS = []


def get_historical_data():
    data = []
    with open('/home/user/data/historical_context.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = int(row['timestamp'])
            val = float(row['value']) if row['value'] else None
            data.append([ts, val])

    # Linear interpolation
    for i in range(len(data)):
        if data[i][1] is None:
            prev_idx = i - 1
            while prev_idx >= 0 and data[prev_idx][1] is None:
                prev_idx -= 1
            next_idx = i + 1
            while next_idx < len(data) and data[next_idx][1] is None:
                next_idx += 1

            if prev_idx >= 0 and next_idx < len(data):
                x0 = data[prev_idx][0]
                y0 = data[prev_idx][1]
                x1 = data[next_idx][0]
                y1 = data[next_idx][1]
                x = data[i][0]
                data[i][1] = y0 + (x - x0) * (y1 - y0) / (x1 - x0)
            elif prev_idx >= 0:
                data[i][1] = data[prev_idx][1]
            elif next_idx < len(data):
                data[i][1] = data[next_idx][1]
    return data


def compute_expected_response(new_points):
    data = get_historical_data()
    data.extend([[ts, val] for ts, val in new_points])
    data.sort(key=lambda x: x[0])

    buckets = {}
    for ts, val in data:
        bucket_ts = (ts // 15) * 15
        buckets.setdefault(bucket_ts, []).append(val)

    sorted_buckets = sorted(buckets)
    bucket_means = {
        b: sum(buckets[b]) / len(buckets[b]) for b in sorted_buckets
    }
    new_bucket_timestamps = {(ts // 15) * 15 for ts, _ in new_points}

    results = []
    for i, b in enumerate(sorted_buckets):
        if b not in new_bucket_timestamps:
            continue
        start_idx = max(0, i - 3)
        window = [bucket_means[sorted_buckets[j]] for j in range(start_idx, i + 1)]
        rolling_avg = sum(window) / len(window)
        mean_val = bucket_means[b]
        diff = abs(mean_val - rolling_avg) / rolling_avg if rolling_avg != 0 else 0
        results.append({
            "bucket_start_time": datetime.fromtimestamp(
                b, tz=timezone.utc
            ).strftime('%Y-%m-%dT%H:%M:%SZ'),
            "mean_value": mean_val,
            "rolling_avg": rolling_avg,
            "is_anomaly": diff > 0.15,
        })
    return results


def encode_points(points_with_ids):
    payloads = []
    numeric_points = []
    for ts, sensor_id, val in points_with_ids:
        csv_line = f"{ts},{sensor_id},{val}"
        payload = binascii.hexlify(csv_line.encode('ascii')).decode('ascii')
        payloads.append(payload)
        numeric_points.append([ts, float(val)])
    SENT_PAYLOADS.extend(payloads)
    return payloads, numeric_points


def assert_response(req_body, expected_points):
    resp = requests.post(URL, headers=AUTH_HEADER, json=req_body, timeout=10)
    assert resp.status_code == 200, (
        f"Expected 200 OK, got {resp.status_code}. Body: {resp.text}"
    )

    resp_data = resp.json()
    expected_data = compute_expected_response(expected_points)
    assert isinstance(resp_data, list), "Response must be a JSON array"
    assert len(resp_data) == len(expected_data), (
        f"Expected {len(expected_data)} buckets, got {len(resp_data)}"
    )

    for i in range(len(expected_data)):
        exp = expected_data[i]
        act = resp_data[i]
        assert isinstance(act, dict), f"Bucket at index {i} is not an object"
        assert set(act) == EXPECTED_KEYS, f"Unexpected response fields at index {i}"
        assert act["bucket_start_time"] == exp["bucket_start_time"], (
            f"Bucket time mismatch at index {i}"
        )
        assert isinstance(act["mean_value"], (int, float)) and not isinstance(act["mean_value"], bool)
        assert isinstance(act["rolling_avg"], (int, float)) and not isinstance(act["rolling_avg"], bool)
        assert math.isclose(act["mean_value"], exp["mean_value"], rel_tol=1e-3), (
            f"Mean value mismatch at index {i}: expected {exp['mean_value']}, "
            f"got {act['mean_value']}"
        )
        assert math.isclose(act["rolling_avg"], exp["rolling_avg"], rel_tol=1e-3), (
            f"Rolling avg mismatch at index {i}: expected {exp['rolling_avg']}, "
            f"got {act['rolling_avg']}"
        )
        assert type(act["is_anomaly"]) is bool
        assert act["is_anomaly"] == exp["is_anomaly"], (
            f"Anomaly mismatch at index {i}: expected {exp['is_anomaly']}, "
            f"got {act['is_anomaly']}"
        )


def test_unauthorized():
    resp = requests.post(URL, json={"stream_id": "test", "payloads": []}, timeout=10)
    assert resp.status_code == 401, (
        f"Expected 401 Unauthorized, got {resp.status_code}"
    )
    resp = requests.post(
        URL,
        headers={"Authorization": "Bearer incorrect-token"},
        json={"stream_id": secrets.token_hex(5), "payloads": []},
        timeout=10,
    )
    assert resp.status_code == 401, (
        f"Expected 401 Unauthorized for invalid token, got {resp.status_code}"
    )


def test_telemetry_processing():
    # Preserve the original fixed behavioral check.
    base_ts = 1715505310
    points = [
        [base_ts, "s1", "42.0"],
        [base_ts + 1, "s1", "42.5"],
        [base_ts + 16, "s1", "80.0"],
    ]
    payloads, numeric_points = encode_points(points)
    assert_response(
        {"stream_id": "alpha-grid", "payloads": payloads},
        numeric_points,
    )


def test_unpredictable_telemetry_batches():
    rng = random.SystemRandom()

    # Each request uses a fresh stream, randomized values and sensor IDs, and a
    # different timestamp layout spanning multiple strict bucket boundaries.
    for case_index in range(4):
        jitter = rng.randrange(0, 3)
        base = 1715505300 + case_index * 2
        offsets = [jitter, 4 + jitter, 15 + jitter, 16 + jitter, 30 + jitter, 46 + jitter]
        points = []
        for point_index, offset in enumerate(offsets):
            sensor_id = f"sensor-{secrets.token_hex(4)}-{point_index}"
            value = round(rng.uniform(7.0, 115.0), 6)
            points.append([base + offset, sensor_id, f"{value:.6f}"])

        payloads, numeric_points = encode_points(points)
        body = {
            "stream_id": f"stream-{secrets.token_hex(10)}-{case_index}",
            "payloads": payloads,
        }
        assert_response(body, numeric_points)


def test_zz_decoder_was_invoked_for_every_payload():
    marker = os.environ["SENSOR_MARKER"]
    with open(marker, "r") as f:
        observed = [line.strip() for line in f if line.strip()]

    observed_counts = collections.Counter(observed)
    expected_counts = collections.Counter(SENT_PAYLOADS)
    assert SENT_PAYLOADS, "No authenticated payloads were exercised"
    for payload, count in expected_counts.items():
        assert observed_counts[payload] >= count, (
            "The service did not invoke /app/sensor_decode for every submitted payload"
        )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
STATUS=$?

# Restore the supplied decoder after instrumentation.
rm -f "$DECODER"
mv "$REAL_DECODER" "$DECODER" 2>/dev/null || true
rm -f "$MARKER"

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
