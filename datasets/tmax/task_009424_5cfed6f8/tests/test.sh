#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import stat
import subprocess
from decimal import Decimal

import pytest

SCRIPT = "/home/user/pipeline.sh"
SOURCE = "/home/user/sensor_data.csv"
REDUCED = "/home/user/reduced_data.csv"
MODEL = "/home/user/best_model.txt"
THRESHOLDS = [30, 40, 42, 50]


def run_pipeline():
    env = os.environ.copy()
    # A compliant script must explicitly select the C locale rather than rely
    # on the verifier's inherited locale.
    env["LANG"] = "C.UTF-8"
    env["LC_ALL"] = "C.UTF-8"
    result = subprocess.run(
        [SCRIPT], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_source_rows():
    with open(SOURCE, newline="") as f:
        rows = list(csv.reader(f))
    assert rows[0] == ["id", "sensor_1", "sensor_2", "sensor_3", "is_anomaly"]
    assert len(rows) == 61, "sensor_data.csv must contain its header and 60 data rows"
    return rows


def expected_projection(rows):
    keep = [0]
    for index in (1, 2, 3):
        values = [Decimal(row[index]) for row in rows[1:]]
        if max(values) != min(values):
            keep.append(index)
    keep.append(4)
    return [[row[index] for index in keep] for row in rows]


def expected_best_thresholds(rows):
    fold_averages = {}
    for threshold in THRESHOLDS:
        fold_accuracies = []
        for start in (0, 20, 40):
            fold = rows[1 + start:1 + start + 20]
            correct = sum(
                (1 if Decimal(row[3]) > threshold else 0) == int(row[4])
                for row in fold
            )
            fold_accuracies.append(correct / 20.0)
        fold_averages[threshold] = sum(fold_accuracies) / 3.0
    maximum = max(fold_averages.values())
    return {t for t, score in fold_averages.items() if abs(score - maximum) < 1e-12}


def assert_outputs_match_input():
    source_rows = read_source_rows()

    assert os.path.isfile(REDUCED), f"Missing intermediate dataset: {REDUCED}"
    assert stat.S_ISREG(os.stat(REDUCED, follow_symlinks=False).st_mode), \
        f"{REDUCED} must be a regular file"
    with open(REDUCED, newline="") as f:
        actual_rows = list(csv.reader(f))
    assert actual_rows == expected_projection(source_rows), (
        "reduced_data.csv must contain all 60 rows and exactly the id, varying "
        "sensor columns, and is_anomaly columns in their original order and values"
    )

    assert os.path.isfile(MODEL), f"Missing output file: {MODEL}"
    assert stat.S_ISREG(os.stat(MODEL, follow_symlinks=False).st_mode), \
        f"{MODEL} must be a regular file"
    with open(MODEL) as f:
        content = f.read().strip()
    match = re.fullmatch(r"Best Threshold: (30|40|42|50)", content)
    assert match, f"Invalid best_model.txt contents: {content!r}"
    actual = int(match.group(1))
    expected = expected_best_thresholds(source_rows)
    assert actual in expected, f"Threshold {actual} is not optimal; expected one of {sorted(expected)}"


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    run_pipeline()


def test_pipeline_script_exists_and_executable():
    """Check if the pipeline script exists and is executable."""
    assert os.path.isfile(SCRIPT), f"Missing script file: {SCRIPT}"
    assert stat.S_ISREG(os.stat(SCRIPT, follow_symlinks=False).st_mode), \
        f"Script {SCRIPT} must be a regular file."
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT} is not executable by the user."


def test_shell_locale_and_implementation_constraints():
    with open(SCRIPT, errors="replace") as f:
        source = f.read()
    assert source.startswith("#!") and "bash" in source.splitlines()[0], \
        "pipeline.sh must be a Bash script with a Bash shebang"
    assert re.search(
        r"(?m)^\s*(?:export\s+)?(?:LC_ALL|LC_NUMERIC)\s*=\s*['\"]?C['\"]?(?:\s|;|$)",
        source,
    ), "pipeline.sh must explicitly set LC_ALL=C or LC_NUMERIC=C"

    executable_text = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    forbidden = re.compile(
        r"(?:^|[;&|]|\$\()\s*(?:env\s+)?(?:/[^\s;|]+/)?(?:python\d*|perl|ruby|Rscript)(?:\s|$)",
        re.IGNORECASE | re.MULTILINE,
    )
    assert not forbidden.search(executable_text), \
        "pipeline.sh may not invoke Python, Perl, Ruby, or R"
    for threshold in THRESHOLDS:
        assert re.search(rf"(?<![0-9]){threshold}(?![0-9])", executable_text), \
            f"pipeline.sh must include threshold {threshold} in its tuning grid"
    assert re.search(r"fold", executable_text, re.IGNORECASE), \
        "pipeline.sh must implement the requested fold-based validation"


def test_reduced_data_csv():
    """Check if reduced_data.csv was created and dropped zero-variance columns."""
    assert os.path.isfile(REDUCED), f"Missing intermediate dataset: {REDUCED}"
    with open(REDUCED) as f:
        lines = f.readlines()
    assert len(lines) > 0, f"File {REDUCED} is empty."
    header = lines[0].strip().split(",")
    assert "id" in header, "Column 'id' is missing in reduced_data.csv"
    assert "is_anomaly" in header, "Column 'is_anomaly' is missing in reduced_data.csv"
    assert "sensor_1" not in header, "Column 'sensor_1' has zero variance and should have been dropped."
    assert "sensor_3" in header, "Column 'sensor_3' has variance and should be kept."
    assert_outputs_match_input()


def test_best_model_txt():
    """Check if best_model.txt contains the correct output for the supplied data."""
    assert os.path.isfile(MODEL), f"Missing output file: {MODEL}"
    with open(MODEL) as f:
        content = f.read().strip()
    expected_content = "Best Threshold: 42"
    assert content == expected_content, \
        f"Expected content '{expected_content}' in {MODEL}, but found '{content}'"


def make_dataset(target, seed):
    rng = random.Random(seed)
    # Every fold includes values distinguishing all adjacent grid thresholds.
    anchors = [25, 31, 35, 39, 41, 42, 43, 47, 49, 51, 55, 60]
    rows = [["id", "sensor_1", "sensor_2", "sensor_3", "is_anomaly"]]
    for i in range(1, 61):
        sensor3 = Decimal(anchors[(i - 1) % len(anchors)]) + Decimal(rng.randrange(0, 10)) / Decimal(100)
        sensor1 = Decimal(i) / Decimal(10) if target in (30, 42) else Decimal("7.5")
        sensor2 = Decimal("11.0") if target in (30, 50) else Decimal((i * 7) % 23)
        anomaly = 1 if sensor3 > target else 0
        rows.append([
            str(i), format(sensor1, "f"), format(sensor2, "f"),
            format(sensor3, "f"), str(anomaly),
        ])
    return rows


def test_pipeline_recomputes_outputs_for_data_and_all_grid_choices():
    with open(SOURCE, "rb") as f:
        original = f.read()
    try:
        seed = int.from_bytes(os.urandom(8), "big")
        for offset, target in enumerate(THRESHOLDS):
            rows = make_dataset(target, seed + offset)
            with open(SOURCE, "w", newline="") as f:
                csv.writer(f, lineterminator="\n").writerows(rows)
            for path in (REDUCED, MODEL):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            run_pipeline()
            assert_outputs_match_input()
            with open(MODEL) as f:
                assert f.read().strip() == f"Best Threshold: {target}"
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original)
        run_pipeline()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
