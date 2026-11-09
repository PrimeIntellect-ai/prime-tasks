#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import csv
import os
import shutil
import stat
import subprocess
import tempfile

HOME = "/home/user"
PIPELINE = os.path.join(HOME, "run_pipeline.sh")
DATA = os.path.join(HOME, "data.csv")
PREDICT = os.path.join(HOME, "predict.sh")
EVALUATE = os.path.join(HOME, "evaluate.awk")
RESULTS = os.path.join(HOME, "tuning_results.csv")
BEST = os.path.join(HOME, "best_threshold.txt")
THRESHOLDS = [10, 20, 30, 40, 50]


def run_pipeline():
    result = subprocess.run(
        [PIPELINE], cwd=HOME, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=25
    )
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with status {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_results():
    assert os.path.isfile(RESULTS), f"Missing file: {RESULTS}"
    with open(RESULTS, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "tuning_results.csv is empty"
    assert rows[0] == ["threshold", "accuracy", "time_ms"], (
        f"Incorrect header in tuning_results.csv: {rows[0]}"
    )
    assert len(rows) == 6, (
        f"Expected 5 data rows in tuning_results.csv, got {len(rows)-1}"
    )
    parsed = {}
    for row in rows[1:]:
        assert len(row) == 3, f"Row does not have 3 columns: {row}"
        threshold, accuracy, time_ms = row
        assert threshold not in parsed, f"Duplicate threshold: {threshold}"
        try:
            acc_val = float(accuracy)
        except ValueError:
            raise AssertionError(f"Accuracy is not a float: {accuracy}")
        try:
            time_val = float(time_ms)
        except ValueError:
            raise AssertionError(f"time_ms is not a number: {time_ms}")
        assert time_val > 0, f"Expected positive time_ms, got {time_val}"
        parsed[threshold] = (acc_val, time_val)
    return parsed


def check_original_assertions():
    assert os.path.isfile(BEST), f"Missing file: {BEST}"
    with open(BEST) as f:
        content = f.read().strip()
    assert content == "30", (
        f"Expected best threshold to be '30', but got '{content}'"
    )

    expected_accuracies = {
        "10": 0.8,
        "20": 0.9,
        "30": 1.0,
        "40": 0.9,
        "50": 0.8,
    }
    parsed = read_results()
    assert set(parsed) == set(expected_accuracies), (
        "Missing thresholds in tuning_results.csv"
    )
    for threshold, expected in expected_accuracies.items():
        actual = parsed[threshold][0]
        assert abs(actual - expected) < 1e-5, (
            f"Expected accuracy {expected} for threshold {threshold}, got {actual}"
        )


def check_evaluator():
    assert os.path.isfile(EVALUATE), f"Missing file: {EVALUATE}"
    cases = [
        (
            "id,score,label,prediction\n"
            "a,3,0,0\n"
            "b,7,1,0\n"
            "c,9,1,1\n"
            "d,2,0,0\n",
            0.75,
        ),
        (
            "id,score,label,prediction\n"
            "x,1,1,0\n"
            "y,2,0,1\n"
            "z,3,1,0\n",
            0.0,
        ),
    ]
    for joined_csv, expected in cases:
        result = subprocess.run(
            ["awk", "-f", EVALUATE], input=joined_csv, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
        )
        assert result.returncode == 0, f"evaluate.awk failed: {result.stderr}"
        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert len(lines) == 1, (
            f"evaluate.awk must print one float, but printed: {result.stdout!r}"
        )
        try:
            value = float(lines[0])
        except ValueError:
            raise AssertionError(f"evaluate.awk did not print a float: {lines[0]!r}")
        assert abs(value - expected) < 1e-6, (
            f"evaluate.awk returned {value}, expected {expected}"
        )


def check_instrumented_run(original_predict, log_path):
    records = [
        (107, 14, 0),
        (102, 22, 1),
        (109, 29, 0),
        (101, 3, 0),
        (108, 47, 0),
        (103, 31, 1),
        (106, 88, 1),
        (104, 53, 1),
        (105, 39, 1),
    ]
    with open(DATA, "w") as f:
        f.write("id,score,label\n")
        for record in records:
            f.write(",".join(map(str, record)) + "\n")

    wrapper = f'''#!/bin/bash
threshold="$1"
input="$2"
pid="$$"
start="$(date +%s%N)"
echo "START,$pid,$threshold,$input,$start" >> {log_path!r}
{original_predict!r} "$@" >/dev/null || exit $?
sleep "$(awk -v t="$threshold" 'BEGIN {{ printf "%.2f", (t/10)*0.03 }}')"
echo "id,prediction"
awk -F, -v t="$threshold" 'NR > 1 {{ p=(($1 + int(t/10)) % 3 == 0) ? 1 : 0; print $1 "," p }}' "$input"
end="$(date +%s%N)"
echo "END,$pid,$threshold,$input,$end" >> {log_path!r}
'''
    with open(PREDICT, "w") as f:
        f.write(wrapper)
    os.chmod(PREDICT, 0o755)
    open(log_path, "w").close()

    run_pipeline()
    parsed = read_results()
    assert set(parsed) == {str(t) for t in THRESHOLDS}, (
        f"Expected exactly thresholds {THRESHOLDS}, got {sorted(parsed)}"
    )

    expected = {}
    for threshold in THRESHOLDS:
        correct = 0
        for ident, score, label in records:
            prediction = 1 if (ident + threshold // 10) % 3 == 0 else 0
            correct += prediction == label
        expected[str(threshold)] = correct / len(records)

    for threshold, expected_accuracy in expected.items():
        actual = parsed[threshold][0]
        assert abs(actual - expected_accuracy) < 1e-5, (
            f"For controlled predictor output, threshold {threshold} should have "
            f"accuracy {expected_accuracy}, got {actual}"
        )

    expected_best = min(
        THRESHOLDS, key=lambda t: (-expected[str(t)], t)
    )
    assert os.path.isfile(BEST), f"Missing file: {BEST}"
    with open(BEST) as f:
        best_content = f.read().strip()
    assert best_content == str(expected_best), (
        f"Expected dynamically derived best threshold {expected_best}, got {best_content!r}"
    )

    starts = {}
    ends = {}
    with open(log_path) as f:
        lines = [line.strip().split(",", 4) for line in f if line.strip()]
    assert len(lines) == 10, (
        f"predict.sh must be invoked once for each threshold; log was {lines}"
    )
    for fields in lines:
        assert len(fields) == 5, f"Malformed predictor invocation log: {fields}"
        event, pid, threshold, input_path, timestamp = fields
        assert threshold in {str(t) for t in THRESHOLDS}, (
            f"Unexpected predictor threshold: {threshold}"
        )
        assert os.path.basename(input_path) == "data.csv", (
            f"predict.sh was not run on data.csv: {input_path}"
        )
        target = starts if event == "START" else ends if event == "END" else None
        assert target is not None, f"Unknown predictor log event: {event}"
        assert pid not in target, f"Duplicate predictor log event for PID {pid}"
        target[pid] = (threshold, int(timestamp))

    assert set(starts) == set(ends), "Some predict.sh invocations did not complete"
    seen = []
    for pid, (threshold, start_ns) in starts.items():
        end_threshold, end_ns = ends[pid]
        assert end_threshold == threshold
        seen.append(threshold)
        measured_ms = (end_ns - start_ns) / 1_000_000.0
        reported_ms = parsed[threshold][1]
        assert abs(reported_ms - measured_ms) <= 75.0, (
            f"time_ms for threshold {threshold} was {reported_ms}, but the "
            f"instrumented predict.sh invocation took {measured_ms:.1f} ms"
        )
    assert sorted(map(int, seen)) == THRESHOLDS, (
        f"predict.sh was not invoked exactly once for every threshold: {seen}"
    )


def main():
    assert os.path.isfile(PIPELINE), f"Missing file: {PIPELINE}"
    assert os.access(PIPELINE, os.X_OK) or os.stat(PIPELINE).st_mode & stat.S_IXUSR, (
        f"File is not executable: {PIPELINE}"
    )
    assert os.path.isfile(PREDICT), f"Missing black-box model: {PREDICT}"
    assert os.path.isfile(DATA), f"Missing dataset: {DATA}"

    with tempfile.TemporaryDirectory(prefix="pipeline_verifier_") as temp:
        saved_data = os.path.join(temp, "data.csv")
        saved_predict = os.path.join(temp, "predict.sh")
        log_path = os.path.join(temp, "predict.log")
        shutil.copy2(DATA, saved_data)
        shutil.copy2(PREDICT, saved_predict)
        try:
            run_pipeline()
            check_original_assertions()
            check_evaluator()
            check_instrumented_run(saved_predict, log_path)
        finally:
            shutil.copy2(saved_data, DATA)
            shutil.copy2(saved_predict, PREDICT)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
