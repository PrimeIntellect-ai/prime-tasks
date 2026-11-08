#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import json
import os
import subprocess

import pandas as pd
import pytest

RAW_DATA = """id,feature_a,click_count
1,0.5,10
2,0.8,
3,0.1,5
"""

ORIGINAL_ETL = """import pandas as pd

def process_data():
    df = pd.read_csv('/home/user/raw_data.csv')
    # Missing schema enforcement for click_count
    df.to_parquet('/home/user/processed_data.parquet', index=False)

if __name__ == "__main__":
    process_data()
"""

EXPECTED_BENCHMARK = """import pandas as pd
import time
import json
import sys

def run_inference():
    try:
        df = pd.read_parquet('/home/user/processed_data.parquet')
    except Exception as e:
        print(f"Failed to read parquet: {e}")
        sys.exit(1)

    # Enforce strict schema validation
    dtype_str = str(df['click_count'].dtype)
    if dtype_str != 'Int64':
        print(f"Schema enforcement failed: click_count is {dtype_str}, expected Int64")
        sys.exit(1)

    start_time = time.time()
    # Simulate inference latency
    time.sleep(0.1)
    duration = time.time() - start_time

    metrics = {
        "status": "success",
        "inference_time_sec": duration,
        "model_version": "v1.2",
        "experiment_id": "exp_773",
        "records_processed": len(df)
    }

    with open('/home/user/experiment_results.json', 'w') as f:
        json.dump(metrics, f)
    print("Benchmarking completed successfully.")

if __name__ == "__main__":
    run_inference()
"""


def expected_dataframe():
    df = pd.read_csv(io.StringIO(RAW_DATA))
    df["click_count"] = df["click_count"].astype("Int64")
    return df


def assert_raw_data_unchanged():
    actual = pd.read_csv("/home/user/raw_data.csv")
    expected = pd.read_csv(io.StringIO(RAW_DATA))
    pd.testing.assert_frame_equal(actual, expected, check_dtype=True)


def assert_processed_data_correct():
    parquet_path = "/home/user/processed_data.parquet"
    assert os.path.exists(parquet_path), (
        f"File {parquet_path} does not exist. Did you run the ETL pipeline script?"
    )
    assert os.path.isfile(parquet_path), f"{parquet_path} is not a regular file"

    actual = pd.read_parquet(parquet_path)
    assert "click_count" in actual.columns, "click_count column is missing"
    assert actual["click_count"].dtype.name == "Int64", (
        f"Expected Int64, got {actual['click_count'].dtype.name}"
    )
    pd.testing.assert_frame_equal(actual, expected_dataframe(), check_dtype=True)


@pytest.fixture(scope="session", autouse=True)
def execute_required_scripts():
    etl_path = "/home/user/etl_pipeline.py"
    benchmark_path = "/home/user/benchmark.py"
    parquet_path = "/home/user/processed_data.parquet"
    results_path = "/home/user/experiment_results.json"

    assert os.path.isfile(etl_path), f"ETL script {etl_path} is missing"
    assert os.path.isfile(benchmark_path), f"Benchmark script {benchmark_path} is missing"
    assert_raw_data_unchanged()

    with open(etl_path, "r") as f:
        etl_source = f.read()
    assert etl_source != ORIGINAL_ETL, "etl_pipeline.py was not modified"
    assert "Int64" in etl_source, "etl_pipeline.py does not explicitly specify the Int64 dtype"

    with open(benchmark_path, "r") as f:
        assert f.read() == EXPECTED_BENCHMARK, "benchmark.py was modified"

    for path in (parquet_path, results_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    etl_result = subprocess.run(
        ["python3", etl_path], capture_output=True, text=True, timeout=30
    )
    assert etl_result.returncode == 0, (
        f"ETL pipeline failed. stdout: {etl_result.stdout}\nstderr: {etl_result.stderr}"
    )
    assert_raw_data_unchanged()
    assert_processed_data_correct()

    with open(benchmark_path, "r") as f:
        assert f.read() == EXPECTED_BENCHMARK, "benchmark.py was modified by the ETL pipeline"

    benchmark_result = subprocess.run(
        ["python3", benchmark_path], capture_output=True, text=True, timeout=30
    )
    assert benchmark_result.returncode == 0, (
        f"Benchmark failed. stdout: {benchmark_result.stdout}\n"
        f"stderr: {benchmark_result.stderr}"
    )

    assert_raw_data_unchanged()
    assert_processed_data_correct()


def test_experiment_results_exist_and_successful():
    results_path = "/home/user/experiment_results.json"
    assert os.path.exists(results_path), (
        f"File {results_path} does not exist. Did you run the benchmark script?"
    )

    with open(results_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} is not valid JSON.")

    assert "status" in results, f"'status' key missing in {results_path}"
    assert results["status"] == "success", (
        f"Expected status 'success', but got '{results['status']}'"
    )
    assert results["model_version"] == "v1.2"
    assert results["experiment_id"] == "exp_773"
    assert results["records_processed"] == len(expected_dataframe())
    assert isinstance(results["inference_time_sec"], (int, float))
    assert 0.09 <= results["inference_time_sec"] < 5


def test_parquet_schema_correct():
    assert_processed_data_correct()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
