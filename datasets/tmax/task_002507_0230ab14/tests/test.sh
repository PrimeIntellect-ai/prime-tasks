#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess

import numpy as np
import pandas as pd


def test_datamash_perturbation_fixed_and_built():
    c_file = "/app/datamash-1.20/src/datamash.c"
    assert os.path.isfile(c_file), f"Required source file is missing: {c_file}"
    with open(c_file, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    assert '#error "Deliberate perturbation: remove this line"' not in content, \
        f"The deliberate perturbation is still present in {c_file}."

    candidates = [
        "/app/datamash-1.20/src/datamash",
        "/home/user/.local/bin/datamash",
        "/usr/local/bin/datamash",
    ]
    valid = []
    errors = []
    for binary in candidates:
        if not (os.path.isfile(binary) and os.access(binary, os.X_OK)):
            continue
        try:
            with open(binary, "rb") as f:
                if f.read(4) != b"\x7fELF":
                    errors.append(f"{binary} is not a compiled ELF executable")
                    continue
            version = subprocess.run(
                [binary, "--version"], capture_output=True, text=True, timeout=10
            )
            if version.returncode != 0 or "gnu datamash" not in (version.stdout + version.stderr).lower():
                errors.append(f"{binary} does not identify itself as GNU Datamash")
                continue
            functional = subprocess.run(
                [binary, "-t,", "-g", "1", "sum", "2"],
                input="x,2\nx,3\ny,4\n",
                capture_output=True,
                text=True,
                timeout=10,
            )
            if functional.returncode != 0 or functional.stdout.strip().splitlines() != ["x,5", "y,4"]:
                errors.append(f"{binary} failed a grouping/sum operation: {functional.stderr}")
                continue
            valid.append(binary)
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(f"{binary}: {exc}")

    assert valid, "No compiled, runnable GNU Datamash binary was found. " + "; ".join(errors)


def reference_results(df):
    work = df.copy()
    work["hour"] = np.floor(work["timestamp"] / 3600).astype(int)
    hourly = work.groupby(["hour", "locale"], as_index=False)["access_count"].sum()

    true_anomalies = set()
    metadata = {}
    for loc in hourly["locale"].unique():
        loc_data = hourly[hourly["locale"] == loc].sort_values("hour").reset_index(drop=True)
        for i, row in loc_data.iterrows():
            prev = loc_data["access_count"].iloc[max(0, i - 3):i]
            rolling = float(prev.mean()) if len(prev) else 0.0
            key = (int(row["hour"]), str(loc))
            total = int(row["access_count"])
            metadata[key] = (total, rolling)
            if total > 2.0 * rolling + 10:
                true_anomalies.add(key)
    return true_anomalies, metadata


def run_and_score(script_path, csv_path, df):
    true_anomalies, metadata = reference_results(df)
    result = subprocess.run(
        ["bash", script_path, str(csv_path)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"

    predicted_anomalies = set()
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split(",")
        assert len(parts) == 4, \
            f"Each output row must have exactly hour,locale,total_count,rolling_avg; got: {line!r}"
        try:
            hour = int(parts[0])
            total = int(parts[2])
        except ValueError:
            raise AssertionError(f"Invalid integer hour or total_count in output row: {line!r}")
        assert re.fullmatch(r"-?\d+\.\d{2}", parts[3]), \
            f"rolling_avg must have exactly two decimal places: {line!r}"

        key = (hour, parts[1])
        assert key in metadata, f"Output row does not correspond to an input hour/locale: {line!r}"
        expected_total, expected_rolling = metadata[key]
        assert total == expected_total, \
            f"Incorrect total_count for {key}: got {total}, expected {expected_total}"
        assert parts[3] == f"{expected_rolling:.2f}", \
            f"Incorrect rolling_avg for {key}: got {parts[3]}, expected {expected_rolling:.2f}"
        predicted_anomalies.add(key)

    tp = len(predicted_anomalies & true_anomalies)
    fp = len(predicted_anomalies - true_anomalies)
    fn = len(true_anomalies - predicted_anomalies)
    precision = tp / (tp + fp) if tp + fp else 0
    recall = tp / (tp + fn) if tp + fn else 0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0
    assert f1 >= 0.90, (
        f"F1 Score {f1:.4f} is less than the required threshold of 0.90. "
        f"True anomalies: {len(true_anomalies)}, Predicted: {len(predicted_anomalies)}, "
        f"TP: {tp}, FP: {fp}, FN: {fn}"
    )


def make_original_dataset():
    np.random.seed(42)
    start_time = 1680307200
    locales = ["es-ES", "fr-FR", "de-DE", "en-US"]
    string_ids = ["ui_button_login", "ui_label_welcome", "ui_menu_settings"]
    records = []
    for h in range(50):
        for loc in locales:
            base_count = np.random.randint(10, 50)
            if h >= 3 and np.random.rand() < 0.1:
                base_count = base_count * 3 + 20
            for _ in range(base_count):
                records.append({
                    "timestamp": start_time + h * 3600 + np.random.randint(0, 3600),
                    "locale": loc,
                    "string_id": np.random.choice(string_ids),
                    "access_count": np.random.randint(1, 5),
                })
    return pd.DataFrame(records).sample(frac=1).reset_index(drop=True)


def make_runtime_random_dataset():
    seed = int.from_bytes(os.urandom(16), "big")
    rng = np.random.default_rng(seed)
    base_hour = int(rng.integers(430000, 560000))
    locales = ["es-ES", "fr-FR", "de-DE", "en-US", "pt-BR"]
    string_ids = ["login", "welcome", "settings", "checkout"]
    records = []

    for loc in locales:
        for offset in range(32):
            if offset > 0 and rng.random() < 0.12:
                continue
            total = int(rng.integers(14, 48))
            if offset >= 3 and rng.random() < 0.20:
                total = int(rng.integers(110, 240))
            pieces = int(rng.integers(1, 7))
            cuts = sorted(rng.integers(0, total + 1, size=pieces - 1).tolist())
            values = np.diff([0] + cuts + [total]).tolist()
            for value in values:
                if value == 0:
                    continue
                records.append({
                    "timestamp": (base_hour + offset) * 3600 + int(rng.integers(0, 3600)),
                    "locale": loc,
                    "string_id": string_ids[int(rng.integers(0, len(string_ids)))],
                    "access_count": int(value),
                })
    rng.shuffle(records)
    return pd.DataFrame(records)


def test_detect_anomalies_f1_score(tmp_path):
    script_path = "/home/user/detect_anomalies.sh"
    assert os.path.exists(script_path), f"Script not found at {script_path}"
    assert os.path.isfile(script_path), f"Script path is not a regular file: {script_path}"

    datasets = [make_original_dataset(), make_runtime_random_dataset(), make_runtime_random_dataset()]
    for index, df in enumerate(datasets):
        csv_path = tmp_path / f"hidden_test_logs_{index}.csv"
        df.to_csv(csv_path, index=False)
        run_and_score(script_path, csv_path, df)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
