#!/bin/bash
set -e
mkdir -p /logs/verifier

WORKDIR=$(mktemp -d)
cp -a /home/user/data "$WORKDIR/data"
if [ -f /home/user/report.json ]; then
    cp -a /home/user/report.json "$WORKDIR/report.json"
fi

cleanup() {
    rm -rf /home/user/data
    cp -a "$WORKDIR/data" /home/user/data
    rm -f /home/user/report.json
    if [ -f "$WORKDIR/report.json" ]; then
        cp -a "$WORKDIR/report.json" /home/user/report.json
    fi
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess
import time

SOURCE = "/home/user/mlops_tracker.go"
REPORT = "/home/user/report.json"
DATA = "/home/user/data"
BINARY = "/tmp/mlops_tracker_submission"


def load_vocab(path):
    vocab = {}
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) == 2:
                vocab[parts[0]] = int(parts[1])
    return vocab


def load_jsonl(path):
    data = {}
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            data[record['experiment_id']] = record
    return data


def tokenize(desc, vocab):
    words = desc.lower().split(' ')
    tokens = [vocab.get(w, 0) for w in words]
    if len(tokens) > 5:
        tokens = tokens[:5]
    else:
        tokens.extend([0] * (5 - len(tokens)))
    return tokens


def expected_from_current_inputs():
    vocab = load_vocab(os.path.join(DATA, "vocab.txt"))
    experiments = load_jsonl(os.path.join(DATA, "experiments.jsonl"))
    metrics = load_jsonl(os.path.join(DATA, "metrics.jsonl"))
    joined_keys = sorted(set(experiments).intersection(metrics))

    expected_results = []
    total_squared_error = 0.0
    for exp_id in joined_keys:
        exp = experiments[exp_id]
        met = metrics[exp_id]
        tokens = tokenize(exp['desc'], vocab)
        score = sum(t * w for t, w in zip(tokens, met['weights']))
        expected_results.append({
            "experiment_id": exp_id,
            "computed_score": score,
        })
        error = score - exp['baseline_score']
        total_squared_error += error * error

    expected_mse = total_squared_error / len(joined_keys) if joined_keys else 0.0
    return expected_results, expected_mse


def read_and_check_report(expected_results, expected_mse, require_positive_timing=False, wall_ns=None):
    assert os.path.isfile(REPORT), "/home/user/report.json does not exist."
    with open(REPORT, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/report.json is not valid JSON."

    assert "mse" in report, "Report missing 'mse' field."
    assert "average_inference_ns" in report, "Report missing 'average_inference_ns' field."
    assert "results" in report, "Report missing 'results' field."

    avg = report["average_inference_ns"]
    assert isinstance(avg, (int, float)) and not isinstance(avg, bool), "'average_inference_ns' must be a number."
    assert math.isfinite(avg), "'average_inference_ns' must be finite."
    assert avg >= 0, "'average_inference_ns' cannot be negative."

    assert isinstance(report["mse"], (int, float)) and not isinstance(report["mse"], bool), "'mse' must be a number."
    assert math.isfinite(report["mse"]), "'mse' must be finite."
    assert math.isclose(report["mse"], expected_mse, rel_tol=1e-5, abs_tol=1e-9), f"Expected MSE ~{expected_mse}, got {report['mse']}"

    assert isinstance(report["results"], list), "'results' must be an array."
    assert len(report["results"]) == len(expected_results), f"Expected {len(expected_results)} results, got {len(report['results'])}"
    for i, (expected, actual) in enumerate(zip(expected_results, report["results"])):
        assert actual.get("experiment_id") == expected["experiment_id"], f"Result {i} expected experiment_id {expected['experiment_id']}, got {actual.get('experiment_id')}"
        assert "computed_score" in actual, f"Result {i} missing 'computed_score'"
        score = actual["computed_score"]
        assert isinstance(score, (int, float)) and not isinstance(score, bool) and math.isfinite(score), f"Result {i} computed_score must be a finite number"
        assert math.isclose(score, expected["computed_score"], rel_tol=1e-5, abs_tol=1e-9), f"Result {i} expected computed_score ~{expected['computed_score']}, got {score}"

    if require_positive_timing:
        assert avg > 0, "'average_inference_ns' must contain a positive measured duration for a nonempty workload."
        assert wall_ns is not None
        assert avg * len(expected_results) <= wall_ns * 2 + 1_000_000, "Reported inference duration is not plausible relative to total program runtime."


def write_dynamic_inputs(count, seed):
    rng = random.Random(seed)
    words = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "theta"]
    token_ids = rng.sample(range(3, 500), len(words))
    vocab = dict(zip(words, token_ids))

    with open(os.path.join(DATA, "vocab.txt"), "w") as f:
        for word, token_id in vocab.items():
            f.write(f"{word} {token_id}\n")

    experiments = []
    metrics = []
    for i in range(count):
        exp_id = f"trial_{seed:016x}_{i:05d}"
        desc_words = []
        for _ in range(rng.randint(1, 8)):
            word = rng.choice(words + ["unknown", "missing"])
            if rng.random() < 0.35:
                word = word.upper()
            desc_words.append(word)
        desc = " ".join(desc_words)
        weights = [rng.uniform(-4.0, 4.0) for _ in range(5)]
        tokens = tokenize(desc, vocab)
        score = sum(t * w for t, w in zip(tokens, weights))
        baseline = score + rng.uniform(-7.0, 7.0)
        experiments.append({"experiment_id": exp_id, "desc": desc, "baseline_score": baseline})
        metrics.append({"experiment_id": exp_id, "weights": weights})

    experiments.append({"experiment_id": f"experiment_only_{seed:x}", "desc": "alpha beta", "baseline_score": 0.0})
    metrics.append({"experiment_id": f"metrics_only_{seed:x}", "weights": [1.0] * 5})
    rng.shuffle(experiments)
    rng.shuffle(metrics)

    with open(os.path.join(DATA, "experiments.jsonl"), "w") as f:
        for record in experiments:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")
    with open(os.path.join(DATA, "metrics.jsonl"), "w") as f:
        for record in metrics:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")


def run_binary_and_check(count, seed):
    write_dynamic_inputs(count, seed)
    expected_results, expected_mse = expected_from_current_inputs()
    if os.path.exists(REPORT):
        os.unlink(REPORT)
    start = time.perf_counter_ns()
    proc = subprocess.run([BINARY], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    wall_ns = time.perf_counter_ns() - start
    assert proc.returncode == 0, f"Compiled tracker exited with status {proc.returncode}: {proc.stderr}"
    assert os.path.isfile(REPORT), "Executing the compiled Go program did not generate /home/user/report.json."
    read_and_check_report(expected_results, expected_mse, require_positive_timing=True, wall_ns=wall_ns)


def main():
    # Preserve all checks against the report produced for the supplied inputs.
    initial_results, initial_mse = expected_from_current_inputs()
    read_and_check_report(initial_results, initial_mse)

    assert os.path.isfile(SOURCE), "/home/user/mlops_tracker.go does not exist or is not a regular file."
    with open(SOURCE, "r", encoding="utf-8") as f:
        source_text = f.read()
    timing_api = (
        (re.search(r"\bNow\s*\(", source_text) and re.search(r"\b(Since|Sub|UnixNano|Nanoseconds)\s*\(", source_text))
        or ("testing.Benchmark" in source_text and "NsPerOp" in source_text)
    )
    assert timing_api, "The Go source does not use a standard-library timing mechanism to benchmark inference."

    build = subprocess.run(["go", "build", "-o", BINARY, SOURCE], cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert build.returncode == 0, f"/home/user/mlops_tracker.go does not compile: {build.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Go build did not produce an executable."

    # Fresh unpredictable inputs ensure the report is generated by the program rather than hard-coded.
    run_binary_and_check(900, secrets.randbits(63))
    run_binary_and_check(1300, secrets.randbits(63))


if __name__ == "__main__":
    main()
TEST_EOF

passed=0
if python3 /tmp/test_final_state.py; then
    passed=1
fi

cleanup
trap - EXIT
if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
