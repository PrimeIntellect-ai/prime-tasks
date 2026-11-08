#!/bin/bash
mkdir -p /logs/verifier
PROJECT=/home/user/video_service
VIDEO=/app/incident.mp4
CLIENT_SRC="$PROJECT/src/bin/verifier_grpc_client.rs"
CLIENT_BIN="$PROJECT/target/debug/verifier_grpc_client"
BACKUP="/tmp/incident.mp4.verifier.$$"
STATUS=0

mkdir -p "$PROJECT/src/bin"
cat > "$CLIENT_SRC" <<'RUST_EOF'
pub mod video {
    tonic::include_proto!("video");
}

use video::video_service_client::VideoServiceClient;
use video::Empty;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut client = VideoServiceClient::connect("http://127.0.0.1:50051").await?;
    let response = client.get_frame_count(Empty {}).await?.into_inner();
    println!("{}", response.count);
    Ok(())
}
RUST_EOF
chown user:user "$CLIENT_SRC"

# The submitted Rust project, including main.rs and processor.rs, must compile.
if ! su -s /bin/bash user -c "cd '$PROJECT' && cargo build --bin video_service --bin verifier_grpc_client"; then
    rm -f "$CLIENT_SRC"
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
rm -f "$CLIENT_SRC"

# Exercise the built service on a verifier-selected video, preventing a fixed
# frame-count implementation from passing.
cp "$VIDEO" "$BACKUP"
FRAME_SEED=$((7 + RANDOM % 11))
if ! ffmpeg -loglevel error -y -f lavfi -i "testsrc=duration=1:size=320x240:rate=${FRAME_SEED}" -c:v libx264 "$VIDEO"; then
    mv -f "$BACKUP" "$VIDEO"
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
EXPECTED_COUNT=$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$VIDEO" 2>/dev/null | tr -d '[:space:]')
if ! [[ "$EXPECTED_COUNT" =~ ^[0-9]+$ ]]; then
    mv -f "$BACKUP" "$VIDEO"
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
export EXPECTED_COUNT CLIENT_BIN

# Replace any previously launched submitted binary and require the newly built
# artifact itself to remain alive and own the service ports.
pkill -x video_service 2>/dev/null || true
sleep 1
SERVICE_TOKEN=secret-uptime-token-99 nohup "$PROJECT/target/debug/video_service" >/tmp/video_service_verifier.log 2>&1 &
SERVICE_PID=$!
sleep 3
if ! kill -0 "$SERVICE_PID" 2>/dev/null; then
    STATUS=1
fi

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import pytest
import requests


def test_recovered_db():
    db_path = "/home/user/video_service/data/recovered.db"
    assert os.path.isfile(db_path), f"Recovered database not found at {db_path}"

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("PRAGMA integrity_check;")
        assert cursor.fetchone() == ("ok",), "recovered.db failed SQLite integrity_check"
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='video_stats';")
        table = cursor.fetchone()
        assert table is not None, "Table 'video_stats' not found in recovered.db"
        cursor.execute("SELECT id, name FROM video_stats;")
        rows = cursor.fetchall()
        assert (1, "test") in rows, f"Original video_stats row was not recovered: {rows}"
        conn.close()
    except sqlite3.DatabaseError as e:
        pytest.fail(f"Recovered file is not a valid SQLite database: {e}")


def test_http_health():
    try:
        response = requests.get("http://127.0.0.1:8080/health", timeout=5)
        assert response.status_code == 200, f"Expected status 200, got {response.status_code}"
        data = response.json()
        assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"
    except requests.RequestException as e:
        pytest.fail(f"HTTP GET /health failed: {e}")


def test_http_metrics_unauthorized():
    try:
        response = requests.get("http://127.0.0.1:8080/metrics", timeout=5)
        assert response.status_code == 401, f"Expected status 401 for unauthorized request, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"HTTP GET /metrics failed: {e}")


def test_http_metrics_authorized():
    try:
        headers = {"Authorization": "Bearer secret-uptime-token-99"}
        response = requests.get("http://127.0.0.1:8080/metrics", headers=headers, timeout=5)
        assert response.status_code == 200, f"Expected status 200 for authorized request, got {response.status_code}"
    except requests.RequestException as e:
        pytest.fail(f"HTTP GET /metrics (authorized) failed: {e}")


def test_grpc_frame_count():
    video_path = "/app/incident.mp4"
    assert os.path.isfile(video_path), f"Video file {video_path} missing"

    try:
        ffprobe_cmd = [
            "ffprobe", "-v", "error", "-select_streams", "v:0",
            "-count_packets", "-show_entries", "stream=nb_read_packets",
            "-of", "csv=p=0", video_path
        ]
        result = subprocess.run(ffprobe_cmd, capture_output=True, text=True, check=True)
        expected_count = int(result.stdout.strip())
        assert expected_count == int(os.environ["EXPECTED_COUNT"])
    except Exception as e:
        pytest.fail(f"Failed to calculate ground truth frame count: {e}")

    try:
        grpc_result = subprocess.run(
            [os.environ["CLIENT_BIN"]], capture_output=True, text=True,
            timeout=10, check=False
        )
        assert grpc_result.returncode == 0, f"gRPC call failed: {grpc_result.stderr}"
        actual_count = int(grpc_result.stdout.strip())
        assert actual_count == expected_count, f"Expected frame count {expected_count}, got {actual_count}"
    except subprocess.TimeoutExpired:
        pytest.fail("gRPC call timed out")
    except ValueError:
        pytest.fail(f"Failed to parse gRPC response: {grpc_result.stdout}")
TEST_EOF

if [ "$STATUS" -eq 0 ]; then
    if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
        STATUS=1
    fi
fi

# Restore the instructed incident video and leave the submitted service running
# against it after verification.
kill "$SERVICE_PID" 2>/dev/null || true
wait "$SERVICE_PID" 2>/dev/null || true
mv -f "$BACKUP" "$VIDEO"
pkill -x video_service 2>/dev/null || true
sleep 1
SERVICE_TOKEN=secret-uptime-token-99 nohup "$PROJECT/target/debug/video_service" >/tmp/video_service.log 2>&1 &
FINAL_PID=$!
sleep 3
if ! kill -0 "$FINAL_PID" 2>/dev/null; then
    STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
