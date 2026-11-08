#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

INPUT_PATH = "/home/user/sensor_data.csv"
CLEANED_PATH = "/home/user/cleaned_data.csv"
DB_PATH = "/home/user/sensors.db"


def true_value(sensor_id, t):
    seed = int(sensor_id.replace('sensor_', ''))
    np.random.seed(seed)
    freq = np.random.uniform(0.01, 0.1)
    phase = np.random.uniform(0, 2 * np.pi)
    return np.sin(freq * t + phase)


def test_rust_pipeline_executes_and_creates_cleaned_csv():
    """Execute the submitted Rust project and require it to produce the cleaned CSV."""
    preferred = Path("/home/user/imputer/Cargo.toml")
    manifests = []
    if preferred.is_file():
        manifests.append(preferred)

    for name in glob.glob("/home/user/**/Cargo.toml", recursive=True):
        path = Path(name)
        if path == preferred or "target" in path.parts or ".cargo" in path.parts:
            continue
        manifests.append(path)

    assert manifests, "No Rust Cargo project was found under /home/user."

    if os.path.exists(CLEANED_PATH):
        os.remove(CLEANED_PATH)

    failures = []
    succeeded = False
    for manifest in manifests[:10]:
        try:
            result = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", str(manifest)],
                cwd=str(manifest.parent),
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=180,
            )
        except (subprocess.TimeoutExpired, OSError) as exc:
            failures.append(f"{manifest}: {exc}")
            continue

        if result.returncode == 0 and os.path.isfile(CLEANED_PATH):
            succeeded = True
            break

        failures.append(
            f"{manifest}: exit={result.returncode}, stderr={result.stderr[-1000:]}"
        )
        if os.path.exists(CLEANED_PATH):
            os.remove(CLEANED_PATH)

    assert succeeded, "No submitted Rust project successfully generated cleaned_data.csv. " + " | ".join(failures)


def test_cleaned_csv_is_complete_and_gap_filled():
    """Require exactly one output record for every input sensor/timestamp pair."""
    assert os.path.isfile(CLEANED_PATH), f"Cleaned CSV {CLEANED_PATH} is missing."

    source = pd.read_csv(INPUT_PATH, dtype={"sensor_id": str})
    cleaned = pd.read_csv(CLEANED_PATH, dtype={"sensor_id": str})

    assert list(cleaned.columns) == ["sensor_id", "timestamp", "value"], \
        "cleaned_data.csv must have exactly the header sensor_id,timestamp,value."
    assert len(source) == 10000, "The supplied input dataset should contain 10,000 records."
    assert len(cleaned) == len(source), \
        f"Expected {len(source)} cleaned records, found {len(cleaned)}."

    assert not source.duplicated(["sensor_id", "timestamp"]).any(), \
        "Input unexpectedly contains duplicate sensor/timestamp keys."
    assert not cleaned.duplicated(["sensor_id", "timestamp"]).any(), \
        "cleaned_data.csv contains duplicate sensor/timestamp keys."

    source_keys = set(zip(source["sensor_id"], source["timestamp"]))
    cleaned_keys = set(zip(cleaned["sensor_id"], cleaned["timestamp"]))
    assert cleaned_keys == source_keys, \
        "cleaned_data.csv does not contain exactly all input sensor/timestamp records."

    cleaned["timestamp"] = pd.to_numeric(cleaned["timestamp"], errors="coerce")
    cleaned["value"] = pd.to_numeric(cleaned["value"], errors="coerce")
    assert cleaned["timestamp"].notna().all(), "A cleaned timestamp is not an integer."
    assert cleaned["value"].notna().all(), "cleaned_data.csv still contains missing values."
    assert np.isfinite(cleaned["value"].to_numpy(dtype=float)).all(), \
        "cleaned_data.csv contains non-finite values."

    observed = source[source["value"].notna()][["sensor_id", "timestamp", "value"]]
    retained = observed.merge(
        cleaned,
        on=["sensor_id", "timestamp"],
        how="left",
        suffixes=("_input", "_cleaned"),
        validate="one_to_one",
    )
    assert np.allclose(
        retained["value_input"].astype(float),
        retained["value_cleaned"].astype(float),
        rtol=1e-10,
        atol=1e-12,
    ), "Existing non-missing sensor values were changed."


def test_sqlite_db_exists():
    """Verify that the SQLite database was created at the correct path."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."


def test_sqlite_schema():
    """Verify the schema of the readings table."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings'")
        table = cursor.fetchone()
        assert table is not None, "Table 'readings' does not exist in the database."

        cursor.execute("PRAGMA table_info(readings)")
        rows = cursor.fetchall()
        columns = {row[1]: row[2].upper() for row in rows}

    expected_columns = {
        'sensor_id': 'TEXT',
        'timestamp': 'INTEGER',
        'value': 'REAL'
    }

    for col, data_type in expected_columns.items():
        assert col in columns, f"Column '{col}' is missing from the 'readings' table."
        assert data_type in columns[col], \
            f"Column '{col}' has incorrect type. Expected {data_type}, got {columns[col]}."


def test_database_contains_complete_cleaned_csv():
    """Verify the bulk import contains exactly the generated cleaned dataset."""
    with sqlite3.connect(DB_PATH) as conn:
        db = pd.read_sql_query("SELECT sensor_id, timestamp, value FROM readings", conn)
    cleaned = pd.read_csv(CLEANED_PATH, dtype={"sensor_id": str})

    assert len(db) == 10000, f"Expected 10,000 database rows, found {len(db)}."
    assert not db.duplicated(["sensor_id", "timestamp"]).any(), \
        "The readings table contains duplicate sensor/timestamp keys."

    joined = cleaned.merge(
        db,
        on=["sensor_id", "timestamp"],
        how="outer",
        suffixes=("_csv", "_db"),
        indicator=True,
        validate="one_to_one",
    )
    assert (joined["_merge"] == "both").all(), \
        "The readings table does not contain exactly the cleaned CSV keys."
    assert np.allclose(
        pd.to_numeric(joined["value_csv"], errors="coerce"),
        pd.to_numeric(joined["value_db"], errors="coerce"),
        rtol=1e-10,
        atol=1e-12,
    ), "Database values do not match cleaned_data.csv."


def test_imputation_mse():
    """Verify that imputed values meet the original MSE threshold over all records."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings'")
        if not cursor.fetchone():
            pytest.fail("Table 'readings' does not exist in the database.")
        df = pd.read_sql_query("SELECT * FROM readings", conn)

    assert not df.empty, "The 'readings' table is empty."
    assert 'sensor_id' in df.columns, "Missing 'sensor_id' column."
    assert 'timestamp' in df.columns, "Missing 'timestamp' column."
    assert 'value' in df.columns, "Missing 'value' column."
    assert len(df) == 10000, "MSE must be evaluated over all 10,000 input records."

    df['value'] = pd.to_numeric(df['value'], errors='coerce')
    assert df['value'].notna().all(), "The readings table contains missing/non-numeric values."
    df['expected'] = df.apply(lambda row: true_value(row['sensor_id'], row['timestamp']), axis=1)
    mse = np.mean((df['value'] - df['expected']) ** 2)

    threshold = 0.01
    assert mse <= threshold, \
        f"MSE of imputed values is {mse:.6f}, which is greater than the threshold of {threshold}."


def test_interpolation_crate_fixed():
    """Keep the source assertions and execute the repaired interpolation function."""
    lib_path = "/app/interpolation/src/lib.rs"
    spatial_path = "/app/interpolation/src/spatial.rs"

    found_fixed = False
    found_perturbed = False
    for path in [lib_path, spatial_path]:
        if os.path.isfile(path):
            with open(path, "r") as handle:
                content = handle.read()
            if "(b + a)" in content:
                found_perturbed = True
            if "(b - a)" in content:
                found_fixed = True

    assert not found_perturbed, \
        "The perturbed logic `(b + a)` is still present in the interpolation crate."
    assert found_fixed, \
        "The correct logic `(b - a)` was not found in the interpolation crate."

    rng = secrets.SystemRandom()
    cases = []
    for _ in range(12):
        a = rng.uniform(-1000.0, 1000.0)
        b = rng.uniform(-1000.0, 1000.0)
        t = rng.uniform(-0.5, 1.5)
        cases.append((a, b, t, a + (b - a) * t))

    with tempfile.TemporaryDirectory(prefix="crate_behavior_") as tmp:
        Path(tmp, "src").mkdir()
        Path(tmp, "Cargo.toml").write_text(
            '[package]\nname = "verify_interpolation"\nversion = "0.1.0"\nedition = "2021"\n'
            '[dependencies]\ninterpolation = { path = "/app/interpolation" }\n'
        )
        rust_cases = ",\n".join(
            f"({a!r}f64, {b!r}f64, {t!r}f64, {expected!r}f64)"
            for a, b, t, expected in cases
        )
        Path(tmp, "src", "main.rs").write_text(f'''fn main() {{
    let cases = [{rust_cases}];
    for (a, b, t, expected) in cases {{
        let actual = interpolation::lerp_f64(a, b, t);
        let tolerance = 1e-10_f64 * expected.abs().max(1.0);
        assert!((actual - expected).abs() <= tolerance,
                "lerp_f64({{}}, {{}}, {{}}) returned {{}}, expected {{}}",
                a, b, t, actual, expected);
    }}
}}
''')
        result = subprocess.run(
            ["cargo", "run", "--quiet"],
            cwd=tmp,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert result.returncode == 0, \
            "The interpolation crate failed executable lerp behavior tests: " + result.stderr[-2000:]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
