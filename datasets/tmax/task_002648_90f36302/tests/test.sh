#!/bin/bash
set -e
mkdir -p /logs/verifier

ETL_PATH=/home/user/src/run_etl.py
ETL_BACKUP=/tmp/verifier_run_etl_original.py
cp "$ETL_PATH" "$ETL_BACKUP"
restore_etl() {
    cp "$ETL_BACKUP" "$ETL_PATH"
    chmod +x "$ETL_PATH"
}
trap restore_etl EXIT

cat <<'WRAPPER_EOF' > "$ETL_PATH"
#!/usr/bin/env python3
import json
import os
import runpy
import shutil

counter_path = "/tmp/verifier_etl_count"
mode_path = "/tmp/verifier_etl_mode"
capture_dir = "/tmp/verifier_etl_captures"
log_path = "/tmp/verifier_etl_invocations.jsonl"

try:
    with open(counter_path, "r") as f:
        count = int(f.read()) + 1
except (FileNotFoundError, ValueError):
    count = 1
with open(counter_path, "w") as f:
    f.write(str(count))

with open(log_path, "a") as f:
    f.write(json.dumps({"run": count, "seed": os.environ.get("ETL_SEED")}) + "\n")

runpy.run_path("/tmp/verifier_run_etl_original.py", run_name="__main__")

try:
    with open(mode_path, "r") as f:
        mode = f.read().strip()
except FileNotFoundError:
    mode = "normal"

# In the probe run, make only the serialized bytes of the second posterior
# output differ. Its JSON values remain unchanged, so a real exact-output
# reproducibility comparison must report False without affecting CTR results.
if mode == "probe" and count == 2:
    with open("/home/user/output/posteriors.json", "ab") as f:
        f.write(b"\n")

run_dir = os.path.join(capture_dir, f"run_{count}")
os.makedirs(run_dir, exist_ok=True)
shutil.copyfile("/home/user/output/similarity.npy", os.path.join(run_dir, "similarity.npy"))
shutil.copyfile("/home/user/output/posteriors.json", os.path.join(run_dir, "posteriors.json"))
WRAPPER_EOF
chmod +x "$ETL_PATH"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import sys

import numpy as np

SCRIPT_PATH = "/home/user/tests/validate_etl.py"
REPORT_PATH = "/home/user/test_report.json"
OUTPUT_DIR = "/home/user/output"
CAPTURE_DIR = "/tmp/verifier_etl_captures"
COUNT_PATH = "/tmp/verifier_etl_count"
MODE_PATH = "/tmp/verifier_etl_mode"
LOG_PATH = "/tmp/verifier_etl_invocations.jsonl"

EXPECTED_KEYS = {
    "is_reproducible",
    "is_symmetric",
    "top_3_similar_to_0",
    "highest_ctr_item",
    "highest_ctr_value",
}


def load_report():
    assert os.path.exists(REPORT_PATH), f"{REPORT_PATH} was not created."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."
    try:
        with open(REPORT_PATH, "r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{REPORT_PATH} is not valid JSON: {exc}")


def check_structure(report):
    missing = EXPECTED_KEYS - set(report.keys())
    assert not missing, f"Missing keys in test_report.json: {missing}"
    assert isinstance(report["is_reproducible"], bool), "'is_reproducible' must be a boolean."
    assert isinstance(report["is_symmetric"], bool), "'is_symmetric' must be a boolean."
    top = report["top_3_similar_to_0"]
    assert isinstance(top, list), "'top_3_similar_to_0' must be a list."
    assert len(top) == 3, "'top_3_similar_to_0' must contain exactly 3 items."
    assert all(isinstance(x, int) for x in top), "All top-3 items must be integers."
    assert 0 not in top, "Item 0 should be excluded from its own top 3 similar items."
    assert isinstance(report["highest_ctr_item"], int), "'highest_ctr_item' must be an integer."
    assert isinstance(report["highest_ctr_value"], (int, float)), "'highest_ctr_value' must be a float."


def expected_ctr(posteriors):
    max_ctr = -1.0
    max_item = -1
    for item_id_str, params in posteriors.items():
        alpha = params["alpha"]
        beta = params["beta"]
        ctr = alpha / (alpha + beta)
        if ctr > max_ctr:
            max_ctr = ctr
            max_item = int(item_id_str)
    return max_item, round(max_ctr, 4)


def run_and_check(mode, expected_reproducible):
    for path in (CAPTURE_DIR,):
        shutil.rmtree(path, ignore_errors=True)
    for path in (COUNT_PATH, LOG_PATH, REPORT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name in ("similarity.npy", "posteriors.json"):
        try:
            os.remove(os.path.join(OUTPUT_DIR, name))
        except FileNotFoundError:
            pass
    with open(MODE_PATH, "w") as f:
        f.write(mode)

    env = os.environ.copy()
    env.pop("ETL_SEED", None)
    completed = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert completed.returncode == 0, (
        f"validate_etl.py failed in {mode} run.\nSTDOUT:\n{completed.stdout}\nSTDERR:\n{completed.stderr}"
    )

    with open(COUNT_PATH, "r") as f:
        assert int(f.read()) == 2, "validate_etl.py must run the ETL exactly twice."
    with open(LOG_PATH, "r") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    assert len(calls) == 2, "Expected exactly two ETL subprocess invocations."
    assert all(call["seed"] == "42" for call in calls), "Both ETL runs must set ETL_SEED=42."

    run1 = os.path.join(CAPTURE_DIR, "run_1")
    run2 = os.path.join(CAPTURE_DIR, "run_2")
    for run_dir in (run1, run2):
        assert os.path.isfile(os.path.join(run_dir, "similarity.npy"))
        assert os.path.isfile(os.path.join(run_dir, "posteriors.json"))

    with open(os.path.join(run1, "similarity.npy"), "rb") as f:
        sim1_bytes = f.read()
    with open(os.path.join(run2, "similarity.npy"), "rb") as f:
        sim2_bytes = f.read()
    with open(os.path.join(run1, "posteriors.json"), "rb") as f:
        post1_bytes = f.read()
    with open(os.path.join(run2, "posteriors.json"), "rb") as f:
        post2_bytes = f.read()
    actual_reproducible = sim1_bytes == sim2_bytes and post1_bytes == post2_bytes
    assert actual_reproducible is expected_reproducible

    report = load_report()
    check_structure(report)
    assert report["is_reproducible"] is actual_reproducible, (
        "'is_reproducible' does not reflect an exact comparison of both generated files."
    )

    similarity = np.load(os.path.join(run1, "similarity.npy"), allow_pickle=False)
    assert similarity.ndim == 2 and similarity.shape[0] == similarity.shape[1]
    expected_symmetric = bool(np.array_equal(similarity, similarity.T))
    assert report["is_symmetric"] is expected_symmetric, "Incorrect exact symmetry result."

    ordered = np.argsort(similarity[0])[::-1]
    expected_top = [int(i) for i in ordered if int(i) != 0][:3]
    assert report["top_3_similar_to_0"] == expected_top, (
        f"Incorrect top 3. Expected {expected_top}, got {report['top_3_similar_to_0']}."
    )

    with open(os.path.join(run1, "posteriors.json"), "r") as f:
        posteriors = json.load(f)
    max_item, max_value = expected_ctr(posteriors)
    assert report["highest_ctr_item"] == max_item, (
        f"Incorrect 'highest_ctr_item'. Expected {max_item}, got {report['highest_ctr_item']}."
    )
    assert abs(report["highest_ctr_value"] - max_value) < 1e-4, (
        f"Incorrect 'highest_ctr_value'. Expected {max_value}, got {report['highest_ctr_value']}."
    )


assert os.path.exists(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} must be a regular file."

# Exercise the comparison logic on unequal exact output bytes, then perform the
# real seeded validation again so the final report describes the actual ETL.
run_and_check("probe", False)
run_and_check("normal", True)

# Preserve the original verifier's checks against the current posterior output.
current_posteriors_path = "/home/user/output/posteriors.json"
assert os.path.exists(current_posteriors_path), (
    f"{current_posteriors_path} is missing. The ETL script must be run to generate it."
)
with open(current_posteriors_path, "r") as f:
    current_posteriors = json.load(f)
final_report = load_report()
max_item, max_value = expected_ctr(current_posteriors)
assert final_report["is_reproducible"] is True
assert final_report["is_symmetric"] is True
assert final_report["highest_ctr_item"] == max_item
assert abs(final_report["highest_ctr_value"] - max_value) < 1e-4
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
