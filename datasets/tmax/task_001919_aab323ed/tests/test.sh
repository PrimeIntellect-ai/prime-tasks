#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

SCRIPT = "/home/user/analyze_artifacts.sh"
CSV_PATH = "/home/user/artifacts.csv"
REPORT = "/home/user/artifact_report.txt"


def active_source(text):
    return "\n".join(
        line for line in text.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


def test_script_exists_executable_and_contains_bootstrap_work():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = active_source(f.read())

    assert re.search(r"(^|\n)\s*#!.*\b(bash|env\s+bash)\b", open(SCRIPT, encoding="utf-8").read()), \
        "The analysis artifact must be a Bash script."
    assert not re.search(r"(^|[;&|]\s*|\b)(python[0-9]*|perl|ruby|Rscript)(\s|$)", source), \
        "External scripting languages are not allowed."
    assert re.search(r"\b1000\b", source), "Script does not implement B=1000 bootstrap samples."
    assert re.search(r"\b100\b", source), "Script does not implement samples containing 100 values."
    assert re.search(r"\b(for|while|until|seq)\b", source), \
        "Script contains no iteration for generating bootstrap samples."
    assert re.search(r"\bshuf\b|\$\{?RANDOM\}?|\brand\s*\(|/dev/(u)?random|sort\s+-R", source), \
        "Script contains no active random sampling operation."


def expected_feature_and_mean(csv_path):
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        fields = reader.fieldnames[1:]
        rows = list(reader)

    values = {field: [float(row[field]) for row in rows] for field in fields}
    variances = {
        field: sum((x - sum(vals) / len(vals)) ** 2 for x in vals) / len(vals)
        for field, vals in values.items()
    }
    feature = max(fields, key=lambda field: variances[field])
    mean = sum(values[feature]) / len(values[feature])
    return feature, mean


def run_and_validate(expected_feature=None):
    if os.path.exists(REPORT):
        os.remove(REPORT)

    result = subprocess.run(
        [SCRIPT], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
    )
    assert result.returncode == 0, (
        f"Analysis script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), "The executed script did not create artifact_report.txt."

    feature, true_mean = expected_feature_and_mean(CSV_PATH)
    if expected_feature is not None:
        assert feature == expected_feature

    with open(REPORT, encoding="utf-8") as f:
        content = f.read()

    pattern = (
        r"\APrimary Feature: ([A-Za-z_][A-Za-z0-9_]*)\n"
        r"True Mean: ([-+]?\d+\.\d{2})\n"
        r"Bootstrap Grand Mean: ([-+]?\d+\.\d{2})\n"
        r"Accuracy Check Passed: (Yes|No)\n?\Z"
    )
    match = re.fullmatch(pattern, content)
    assert match is not None, "Report does not have the required exact four-line format."

    reported_feature, reported_true, reported_bootstrap, reported_check = match.groups()
    assert reported_feature == feature, f"Expected primary feature {feature}, got {reported_feature}."
    assert f"Primary Feature: {feature}" in content

    expected_true_mean_str = f"True Mean: {true_mean:.2f}"
    assert expected_true_mean_str in content, \
        f"Report missing or incorrect True Mean; expected {expected_true_mean_str}."
    assert math.isclose(float(reported_true), true_mean, abs_tol=0.0051)

    bootstrap_mean = float(reported_bootstrap)
    difference = abs(true_mean - bootstrap_mean)
    expected_check = "Yes" if difference < 0.5 else "No"
    assert reported_check == expected_check, "Accuracy check is inconsistent with the reported means."
    assert "Accuracy Check Passed: Yes" in content
    assert difference < 0.5, \
        f"Bootstrap mean {bootstrap_mean} is not within 0.5 of true mean {true_mean}."


def test_execution_report_and_input_driven_analysis():
    assert os.path.isfile(CSV_PATH), f"Data file {CSV_PATH} is missing."
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()

    # Preserve all original report assertions on the supplied artifact data.
    run_and_validate(expected_feature="memory_mb")

    # Exercise the script on a derived 100-row input whose primary feature differs,
    # preventing a prewritten report or hard-coded memory_mb answer from passing.
    controlled = ["run_id,latency_ms,cpu_usage_pct,memory_mb,validation_loss"]
    for i in range(1, 101):
        latency = "10.0" if i % 2 else "10.8"
        controlled.append(f"{i},{latency},20.0,30.0,0.20")

    try:
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
            f.write("\n".join(controlled) + "\n")
        run_and_validate(expected_feature="latency_ms")
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)

    # Leave and verify the requested final report for the original supplied data.
    run_and_validate(expected_feature="memory_mb")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
