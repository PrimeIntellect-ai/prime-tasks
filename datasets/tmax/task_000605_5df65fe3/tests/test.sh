#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import subprocess
from decimal import Decimal, InvalidOperation

import pytest
import psycopg2
import redis


def test_process_script_execution_and_metrics():
    script_path = "/home/user/process.sh"
    source_path = "/home/user/data/sensors.csv"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    assert os.path.isfile(source_path), f"Source CSV {source_path} does not exist."

    # Run the submitted artifact and measure the complete ETL execution time.
    start_time = time.time()
    res = subprocess.run(["/bin/bash", script_path], capture_output=True, text=True)
    duration = time.time() - start_time

    assert res.returncode == 0, (
        f"process.sh failed with return code {res.returncode}.\n"
        f"Stdout: {res.stdout}\nStderr: {res.stderr}"
    )
    assert duration <= 10.0, f"Execution too slow: {duration:.2f}s (Threshold: <= 10.0s)"

    try:
        conn = psycopg2.connect(dbname="sensor_db", user="postgres", host="localhost")
        cur = conn.cursor()
    except Exception as e:
        pytest.fail(f"Failed to connect to PostgreSQL: {e}")

    try:
        # Preserve the original row-count assertions.
        cur.execute("SELECT COUNT(*) FROM raw_data;")
        raw_count = cur.fetchone()[0]
        assert raw_count == 500000, f"Expected 500000 rows in raw_data, got {raw_count}"

        cur.execute("SELECT COUNT(*) FROM sensor_features;")
        features_count = cur.fetchone()[0]
        assert features_count == 500000, (
            f"Expected 500000 rows in sensor_features, got {features_count}"
        )

        # Load the actual source into a verifier-owned temporary table and compare
        # both directions with EXCEPT ALL so duplicates and values must match.
        cur.execute("""
            CREATE TEMP TABLE expected_raw (
                ts BIGINT,
                sensor_id VARCHAR,
                value NUMERIC
            ) ON COMMIT DROP;
        """)
        with open(source_path, "r", newline="") as source_file:
            cur.copy_expert(
                "COPY expected_raw (ts, sensor_id, value) FROM STDIN WITH (FORMAT CSV)",
                source_file,
            )

        cur.execute("SELECT COUNT(*) FROM expected_raw;")
        source_count = cur.fetchone()[0]
        assert source_count == 500000, (
            f"Expected 500000 rows in sensors.csv, got {source_count}"
        )

        cur.execute("""
            SELECT COUNT(*)
            FROM (
                (SELECT ts, sensor_id, value FROM raw_data
                 EXCEPT ALL
                 SELECT ts, sensor_id, value FROM expected_raw)
                UNION ALL
                (SELECT ts, sensor_id, value FROM expected_raw
                 EXCEPT ALL
                 SELECT ts, sensor_id, value FROM raw_data)
            ) AS raw_differences;
        """)
        raw_differences = cur.fetchone()[0]
        assert raw_differences == 0, (
            f"raw_data does not exactly match sensors.csv ({raw_differences} differing rows)"
        )

        # Independently recompute every rolling average from the source data and
        # compare the complete feature multiset in both directions.
        cur.execute("""
            WITH expected_features AS (
                SELECT
                    ts,
                    sensor_id,
                    AVG(value) OVER (
                        PARTITION BY sensor_id
                        ORDER BY ts ASC
                        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
                    ) AS rolling_avg
                FROM expected_raw
            ),
            feature_differences AS (
                (SELECT ts, sensor_id, rolling_avg FROM sensor_features
                 EXCEPT ALL
                 SELECT ts, sensor_id, rolling_avg FROM expected_features)
                UNION ALL
                (SELECT ts, sensor_id, rolling_avg FROM expected_features
                 EXCEPT ALL
                 SELECT ts, sensor_id, rolling_avg FROM sensor_features)
            )
            SELECT COUNT(*) FROM feature_differences;
        """)
        feature_differences = cur.fetchone()[0]
        assert feature_differences == 0, (
            "sensor_features does not contain the required 5-period rolling averages "
            f"({feature_differences} differing rows)"
        )

        # Derive each expected latest cache value independently from the source.
        cur.execute("""
            WITH computed AS (
                SELECT
                    ts,
                    sensor_id,
                    AVG(value) OVER (
                        PARTITION BY sensor_id
                        ORDER BY ts ASC
                        ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
                    ) AS rolling_avg
                FROM expected_raw
            ),
            latest AS (
                SELECT DISTINCT ON (sensor_id)
                    sensor_id,
                    rolling_avg
                FROM computed
                ORDER BY sensor_id, ts DESC
            )
            SELECT sensor_id, ROUND(rolling_avg, 2)::TEXT
            FROM latest
            ORDER BY sensor_id;
        """)
        expected_cache = {
            f"sensor:{sensor_id}": Decimal(value)
            for sensor_id, value in cur.fetchall()
        }
    except psycopg2.Error as e:
        pytest.fail(f"Database error while validating ETL output: {e}")
    finally:
        cur.close()
        conn.close()

    try:
        r = redis.Redis(host="localhost", port=6379, decode_responses=True)
        r.ping()
    except Exception as e:
        pytest.fail(f"Failed to connect to Redis: {e}")

    # Preserve the original Redis assertions.
    keys = r.keys("sensor:*")
    assert len(keys) > 0, "No keys matching 'sensor:*' found in Redis."

    for k in keys[:50]:
        val = r.get(k)
        try:
            float(val)
            if "." in val:
                decimals = len(val.split(".")[-1])
                assert decimals <= 2, (
                    f"Value {val} for key {k} is not rounded to 2 decimal places."
                )
        except (ValueError, TypeError):
            pytest.fail(f"Redis key {k} has non-numeric value: {val}")

    assert set(keys) == set(expected_cache), (
        f"Redis sensor keys differ from the source sensors; expected "
        f"{len(expected_cache)}, got {len(keys)}"
    )

    for key, expected_value in expected_cache.items():
        actual_text = r.get(key)
        try:
            actual_value = Decimal(actual_text)
        except (InvalidOperation, TypeError):
            pytest.fail(f"Redis key {key} has non-numeric value: {actual_text}")
        assert actual_value.is_finite(), f"Redis key {key} has non-finite value: {actual_text}"
        if "." in actual_text:
            decimals = len(actual_text.split(".")[-1])
            assert decimals <= 2, (
                f"Value {actual_text} for key {key} is not rounded to 2 decimal places."
            )
        assert actual_value == expected_value, (
            f"Redis key {key} has {actual_text}, expected {expected_value}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
