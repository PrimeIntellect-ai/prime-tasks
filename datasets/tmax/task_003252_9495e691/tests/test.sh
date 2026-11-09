#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import stat


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is not executable."


def test_pipeline_uses_scipy_ttest_ind():
    with open("/home/user/pipeline.sh", "r") as f:
        source = f.read().lower()
    assert "scipy" in source, "pipeline.sh does not use SciPy."
    assert "ttest_ind" in source, "pipeline.sh does not call scipy.stats.ttest_ind."


def test_cleaned_data_exists_and_correct():
    cleaned_path = "/home/user/clean_data/cleaned_sensors.csv"
    assert os.path.isfile(cleaned_path), f"Cleaned data file {cleaned_path} does not exist."

    with open(cleaned_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "sensor_id,rack,temperature",
        "1,A,21.1",
        "2,A,21.5",
        "4,A,21.3",
        "6,A,21.2",
        "7,A,21.4",
        "8,B,21.6",
        "9,B,21.8",
        "11,B,21.5",
        "12,B,21.7",
        "13,B,21.9"
    ]

    assert lines == expected_lines, f"Cleaned data in {cleaned_path} does not match expected output."


def test_p_value_output():
    p_value_path = "/home/user/results/p_value.txt"
    assert os.path.isfile(p_value_path), f"Output file {p_value_path} does not exist."

    with open(p_value_path, "r") as f:
        content = f.read().strip()

    assert content == "0.0163", f"Expected p-value to be '0.0163', but got '{content}'."
TEST_EOF

cat <<'TEST_EOF' > /tmp/test_challenge_state.py
import json
import os

with open("/tmp/challenge_expected.json", "r") as f:
    expected = json.load(f)


def test_pipeline_recreated_directories():
    assert os.path.isdir("/home/user/clean_data")
    assert os.path.isdir("/home/user/results")


def test_challenge_input_was_not_modified():
    with open("/home/user/data/raw_sensors.csv", "r") as f:
        assert f.read() == expected["raw"]


def test_challenge_cleaned_data():
    path = "/home/user/clean_data/cleaned_sensors.csv"
    assert os.path.isfile(path)
    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert lines == expected["cleaned"]


def test_challenge_p_value():
    path = "/home/user/results/p_value.txt"
    assert os.path.isfile(path)
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == expected["p_value"]
TEST_EOF

run_verification() {
    rm -rf /home/user/clean_data /home/user/results || return 1
    timeout 60 /home/user/pipeline.sh || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    python3 - <<'PY' || return 1
import json
import secrets
from scipy.stats import ttest_ind

base = 18.0 + secrets.randbelow(6000) / 1000.0
shift = 0.3 + secrets.randbelow(1200) / 1000.0
a = [base - 0.31, base + 0.08, base + 0.27, base - 0.04]
b = [base + shift - 0.22, base + shift + 0.11, base + shift + 0.35, base + shift - 0.07, base + shift + 0.19]
a_text = [f"{x:.3f}" for x in a]
b_text = [f"{x:.3f}" for x in b]
start = 1000 + secrets.randbelow(8000)
rows = [
    [str(start), "A", a_text[0]],
    [str(start + 1), "A", ""],
    [str(start + 2), "B", b_text[0]],
    [str(start + 3), "A", a_text[1]],
    [str(start + 4), "B", "0"],
    [str(start + 5), "B", b_text[1]],
    [str(start + 6), "A", "-3.5"],
    [str(start + 7), "A", a_text[2]],
    [str(start + 8), "B", b_text[2]],
    [str(start + 9), "A", a_text[3]],
    [str(start + 10), "B", b_text[3]],
    [str(start + 11), "B", b_text[4]],
]
header = "sensor_id,rack,temperature"
raw_lines = [header] + [",".join(row) for row in rows]
raw = "\n".join(raw_lines) + "\n"
with open("/home/user/data/raw_sensors.csv", "w") as f:
    f.write(raw)
cleaned = [header] + [",".join(row) for row in rows if row[2] and float(row[2]) > 0]
p_value = f"{ttest_ind([float(x) for x in a_text], [float(x) for x in b_text]).pvalue:.4f}"
with open("/tmp/challenge_expected.json", "w") as f:
    json.dump({"raw": raw, "cleaned": cleaned, "p_value": p_value}, f)
PY

    rm -rf /home/user/clean_data /home/user/results || return 1
    timeout 60 /home/user/pipeline.sh || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_challenge_state.py -x --tb=short || return 1
}

if run_verification 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
