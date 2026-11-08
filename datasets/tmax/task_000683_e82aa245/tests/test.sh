#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/run_analyze_instrumented.py
import json
import os
import runpy
import sys
import traceback

import numpy as np

trace = []
real_seed = np.random.seed
real_beta = np.random.beta

def checked_seed(*args, **kwargs):
    seed_value = args[0] if args else kwargs.get("seed", None)
    try:
        seed_value = int(seed_value) if seed_value is not None else None
    except Exception:
        seed_value = repr(seed_value)
    trace.append({"function": "seed", "seed": seed_value})
    return real_seed(*args, **kwargs)

def checked_beta(a, b, size=None):
    try:
        logged_size = int(size) if size is not None else None
    except Exception:
        logged_size = repr(size)
    trace.append({
        "function": "beta",
        "a": float(a),
        "b": float(b),
        "size": logged_size,
    })
    return real_beta(a, b, size=size)

np.random.seed = checked_seed
np.random.beta = checked_beta
failed = False
try:
    runpy.run_path("/home/user/analyze.py", run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        failed = True
        traceback.print_exc()
except BaseException:
    failed = True
    traceback.print_exc()
finally:
    with open(os.environ["ANALYZE_TRACE"], "w") as f:
        json.dump(trace, f)

if failed:
    sys.exit(1)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import subprocess
import uuid

import numpy as np

SCRIPT_PATH = "/home/user/analyze.py"
DATA_PATH = "/home/user/campaign_data.csv"
REPORT_PATH = "/home/user/report.json"


def run_script(expected_totals):
    assert os.path.isfile(SCRIPT_PATH), f"Expected Python script at {SCRIPT_PATH} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"Expected {SCRIPT_PATH} to be a regular file."

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    trace_path = f"/tmp/analyze_trace_{uuid.uuid4().hex}.json"
    env = os.environ.copy()
    env["ANALYZE_TRACE"] = trace_path
    result = subprocess.run(
        ["python3", "/tmp/run_analyze_instrumented.py"],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), f"Expected report file at {REPORT_PATH} does not exist after execution."
    assert os.path.isfile(trace_path), "Execution trace was not generated."

    with open(trace_path) as f:
        trace = json.load(f)
    os.remove(trace_path)

    alpha_clicks, alpha_conversions = expected_totals["Alpha"]
    beta_clicks, beta_conversions = expected_totals["Beta"]
    assert trace == [
        {"function": "seed", "seed": 42},
        {
            "function": "beta",
            "a": float(alpha_conversions + 1),
            "b": float(alpha_clicks - alpha_conversions + 1),
            "size": 1000000,
        },
        {
            "function": "beta",
            "a": float(beta_conversions + 1),
            "b": float(beta_clicks - beta_conversions + 1),
            "size": 1000000,
        },
    ], "Expected exactly one numpy.random.seed(42) call immediately followed by the two required 1,000,000-sample beta calls."

    with open(REPORT_PATH) as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"The file {REPORT_PATH} does not contain valid JSON: {exc}")


def expected_report(totals):
    alpha_clicks, alpha_conversions = totals["Alpha"]
    beta_clicks, beta_conversions = totals["Beta"]
    rng = np.random.RandomState(42)
    alpha_samples = rng.beta(
        alpha_conversions + 1,
        alpha_clicks - alpha_conversions + 1,
        size=1000000,
    )
    beta_samples = rng.beta(
        beta_conversions + 1,
        beta_clicks - beta_conversions + 1,
        size=1000000,
    )
    return {
        "Alpha": {
            "clicks": alpha_clicks,
            "conversions": alpha_conversions,
            "posterior_mean": round((alpha_conversions + 1) / (alpha_clicks + 2), 5),
        },
        "Beta": {
            "clicks": beta_clicks,
            "conversions": beta_conversions,
            "posterior_mean": round((beta_conversions + 1) / (beta_clicks + 2), 5),
        },
        "prob_alpha_greater_beta": round(float(np.mean(alpha_samples > beta_samples)), 5),
    }


def test_script_and_report():
    with open(DATA_PATH, "rb") as f:
        original_data = f.read()

    random_rows = []
    random_totals = {"Alpha": [0, 0], "Beta": [0, 0]}
    for day in range(1, 6):
        for campaign in ("Beta", "Alpha"):
            clicks = 90 + secrets.randbelow(260)
            conversions = 5 + secrets.randbelow(max(1, clicks // 3 - 5))
            random_rows.append([f"2024-02-{day:02d}", campaign, clicks, conversions])
            random_totals[campaign][0] += clicks
            random_totals[campaign][1] += conversions

    try:
        with open(DATA_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["date", "campaign_id", "clicks", "conversions"])
            writer.writerows(random_rows)

        randomized_report = run_script(random_totals)
        assert randomized_report == expected_report(random_totals), (
            "The report generated for a fresh dataset did not match aggregation, posterior, "
            "rounding, and Monte Carlo results derived by the verifier."
        )
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)

    # Preserve the original verifier's assertions on the supplied dataset.
    report_data = run_script({"Alpha": (1000, 95), "Beta": (1200, 130)})

    assert "Alpha" in report_data, "Missing 'Alpha' key in report.json"
    alpha = report_data["Alpha"]
    assert alpha.get("clicks") == 1000, f"Expected Alpha clicks to be 1000, got {alpha.get('clicks')}"
    assert alpha.get("conversions") == 95, f"Expected Alpha conversions to be 95, got {alpha.get('conversions')}"
    assert abs(alpha.get("posterior_mean", 0) - 0.09581) <= 0.00002, f"Expected Alpha posterior_mean to be approx 0.09581, got {alpha.get('posterior_mean')}"

    assert "Beta" in report_data, "Missing 'Beta' key in report.json"
    beta = report_data["Beta"]
    assert beta.get("clicks") == 1200, f"Expected Beta clicks to be 1200, got {beta.get('clicks')}"
    assert beta.get("conversions") == 130, f"Expected Beta conversions to be 130, got {beta.get('conversions')}"
    assert abs(beta.get("posterior_mean", 0) - 0.10908) <= 0.00002, f"Expected Beta posterior_mean to be approx 0.10908, got {beta.get('posterior_mean')}"

    assert "prob_alpha_greater_beta" in report_data, "Missing 'prob_alpha_greater_beta' key in report.json"
    prob = report_data["prob_alpha_greater_beta"]
    assert abs(prob - 0.13404) <= 0.00002, f"Expected prob_alpha_greater_beta to be approx 0.13404, got {prob}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
