#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import time
import sqlite3
import subprocess
import random
import redis

def test_consumer_performance_and_correctness():
    r = redis.Redis(host='127.0.0.1', port=6379, db=0)
    db_path = "/app/logs.db"

    # 1. Re-seed the Redis queue with 500 random user IDs (1 to 1000)
    r.delete("job_queue")
    test_user_ids = [random.randint(1, 1000) for _ in range(500)]
    for uid in test_user_ids:
        r.rpush("job_queue", uid)

    # 2. Measure execution time of consumer.py
    start_time = time.time()
    result = subprocess.run(["python3", "/app/consumer.py"], capture_output=True, text=True)
    end_time = time.time()

    duration = end_time - start_time

    assert result.returncode == 0, f"consumer.py failed with error: {result.stderr}"
    assert duration <= 1.0, f"Execution time {duration:.2f}s exceeded threshold of 1.0s"
    assert r.llen("job_queue") == 0, "consumer.py did not completely drain the 500-job queue"

    # 3. Verify results.json correctness
    results_path = "/app/results.json"
    assert os.path.exists(results_path), f"{results_path} was not created"

    with open(results_path, "r") as f:
        results = json.load(f)

    assert isinstance(results, dict), "results.json must contain a dictionary"
    expected_keys = {str(uid) for uid in test_user_ids}
    assert set(results.keys()) == expected_keys, (
        "results.json does not contain exactly the user IDs from the queued jobs"
    )

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check all results against the database truth
    for uid_str, total_duration in results.items():
        assert type(total_duration) is int, f"Result for user {uid_str} is not an integer"
        uid = int(uid_str)
        cursor.execute("SELECT SUM(duration) FROM user_logs WHERE user_id = ? AND action = 'video_play'", (uid,))
        row = cursor.fetchone()
        expected_duration = row[0] if row[0] is not None else 0
        assert total_duration == expected_duration, f"Mismatch for user {uid}: expected {expected_duration}, got {total_duration}"

    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
