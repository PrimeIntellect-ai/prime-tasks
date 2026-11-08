#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.metadata
import importlib.util
import os
import runpy

import pandas as pd
import pytest
from sklearn.metrics import mean_squared_error

SCRIPT_PATH = "/home/user/clean_data.py"
OUTPUT_PATH = "/home/user/processed_sensor_data.csv"
RAW_PATH = "/home/user/raw_sensor_data.csv"
CORE_PATH = "/app/ts_processor/ts_processor/core.py"


def expected_from_raw():
    raw = pd.read_csv(RAW_PATH)
    raw["timestamp"] = pd.to_datetime(raw["timestamp"], errors="raise")
    raw["value"] = pd.to_numeric(raw["value"], errors="raise")
    raw = raw[(raw["value"] >= 0) & (raw["value"] <= 100)]
    raw = raw.set_index("timestamp")
    raw = raw[~raw.index.duplicated(keep="first")]
    expected = raw.resample("D").mean().interpolate(method="linear")
    return expected[["value"]]


def assert_processor_behavior(processor):
    idx = pd.to_datetime([
        "2024-02-01", "2024-02-01", "2024-02-04", "2024-02-06"
    ])
    probe = pd.DataFrame({"value": [12.0, 99.0, 42.0, 62.0]}, index=idx)
    result = processor(probe, "D")

    expected_idx = pd.date_range("2024-02-01", "2024-02-06", freq="D")
    expected_values = [12.0, 22.0, 32.0, 42.0, 52.0, 62.0]
    assert isinstance(result, pd.DataFrame)
    assert list(result.columns) == ["value"]
    pd.testing.assert_index_equal(result.index, expected_idx)
    pd.testing.assert_series_equal(
        result["value"],
        pd.Series(expected_values, index=expected_idx, name="value"),
        check_dtype=False,
        check_exact=False,
        rtol=1e-12,
        atol=1e-12,
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script missing at {SCRIPT_PATH}"
    assert os.path.isfile(CORE_PATH), f"Expected package source missing at {CORE_PATH}"
    assert os.path.isfile(RAW_PATH), f"Expected raw data missing at {RAW_PATH}"

    # Confirm the vendored source itself was repaired and works on an independent probe.
    spec = importlib.util.spec_from_file_location("submitted_ts_processor_core", CORE_PATH)
    source_core = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(source_core)
    assert_processor_behavior(source_core.process_and_validate)

    # Confirm the package was installed and that the installed implementation works.
    assert importlib.metadata.version("ts_processor")
    import ts_processor
    import ts_processor.core as installed_core
    assert_processor_behavior(installed_core.process_and_validate)

    # The script must actually call the package function when producing a fresh output.
    source = open(SCRIPT_PATH, "r", encoding="utf-8").read()
    tree = ast.parse(source, filename=SCRIPT_PATH)
    assert any(
        isinstance(node, ast.Call)
        and (
            (isinstance(node.func, ast.Name) and node.func.id == "process_and_validate")
            or (isinstance(node.func, ast.Attribute) and node.func.attr == "process_and_validate")
        )
        for node in ast.walk(tree)
    ), "clean_data.py must call process_and_validate"

    calls = []
    original = installed_core.process_and_validate

    def tracked_processor(df, freq):
        calls.append(freq)
        return original(df, freq)

    ts_processor.process_and_validate = tracked_processor
    installed_core.process_and_validate = tracked_processor
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    try:
        try:
            runpy.run_path(SCRIPT_PATH, run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"clean_data.py exited with status {exc.code}"
    finally:
        ts_processor.process_and_validate = original
        installed_core.process_and_validate = original

    assert calls, "clean_data.py did not use the installed process_and_validate function"
    assert any(freq == "D" for freq in calls), "process_and_validate was not called with daily frequency 'D'"


def test_clean_data_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script missing at {SCRIPT_PATH}"


def test_processed_data_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Expected output data missing at {OUTPUT_PATH}"


def test_processed_data_columns():
    df = pd.read_csv(OUTPUT_PATH)
    expected_columns = ["timestamp", "value"]
    assert list(df.columns) == expected_columns, f"Expected columns {expected_columns}, but got {list(df.columns)}"


def test_processed_data_mse():
    assert os.path.isfile(OUTPUT_PATH), f"Output file missing: {OUTPUT_PATH}"

    pred = pd.read_csv(OUTPUT_PATH, parse_dates=["timestamp"]).set_index("timestamp")
    true = expected_from_raw()

    assert pred.index.is_unique, "Output contains duplicate timestamps"
    assert pred.index.equals(true.index), (
        f"Output timestamps must exactly match the complete daily range; got {list(pred.index)}"
    )
    assert len(pred) == len(true), "Output must contain every expected daily row and no extra rows"
    assert pred["value"].notna().all(), "Output contains missing values"

    mse = mean_squared_error(true["value"], pred["value"])
    threshold = 0.01
    assert mse <= threshold, f"MSE is {mse}, which is greater than the threshold of {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
