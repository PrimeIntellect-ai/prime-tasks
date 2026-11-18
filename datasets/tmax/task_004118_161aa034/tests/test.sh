#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

HOME = "/home/user"
CPP = f"{HOME}/etl_inference.cpp"
SCRIPT = f"{HOME}/run_pipeline.sh"
PREDICTIONS = f"{HOME}/predictions.csv"
BENCHMARK = f"{HOME}/benchmark.txt"
DATA = f"{HOME}/data.csv"
WEIGHTS = f"{HOME}/weights.txt"
PINNED_BINARY = "/tmp/verifier_etl_inference"

CANONICAL_WEIGHTS = """# W1 (Input to Hidden, 3x4 matrix. Row 1 corresponds to weights for x1 into the 4 hidden neurons)
0.1 -0.2 0.3 0.0
-0.1 0.5 0.0 0.2
0.0 0.0 -0.4 0.1
# b1 (Hidden layer biases, 1x4 vector)
0.1 -0.1 0.2 0.0
# W2 (Hidden to Output, 4x1 matrix)
0.5
-0.5
1.0
0.2
# b2 (Output layer bias, scalar)
-0.2
"""

CANONICAL_DATA = """id,v1,v2,v3
1,2.0,3.0,2.718281828
2,1.0,0.0,1.0
3,-1.0,2.0,7.389056099
"""


def run(cmd, timeout=120):
    return subprocess.run(
        cmd, cwd=HOME, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=timeout, check=True
    )


def read_benchmark():
    assert os.path.isfile(BENCHMARK), f"File {BENCHMARK} does not exist. The C++ program failed to create it."
    with open(BENCHMARK, "r") as f:
        content = f.read().strip()
    pattern = r"^Total inference time: \d+ us$"
    assert re.match(pattern, content), (
        f"File {BENCHMARK} content '{content}' does not match expected format "
        "'Total inference time: [X] us'."
    )
    value = int(re.fullmatch(pattern, content).group(0).split()[-2])
    assert value > 0, "The measured inference benchmark must be greater than zero microseconds."
    return value


def assert_predictions(expected):
    assert os.path.isfile(PREDICTIONS), f"File {PREDICTIONS} does not exist. The C++ program failed to create it."
    with open(PREDICTIONS, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == len(expected) + 1, (
        f"File {PREDICTIONS} does not contain exactly the expected number of rows."
    )
    assert lines[0] == "id,pred", (
        f"Header in {PREDICTIONS} is incorrect. Expected 'id,pred', got '{lines[0]}'."
    )

    seen = set()
    for line in lines[1:]:
        parts = line.split(",")
        assert len(parts) == 2, f"Invalid format in line '{line}' of {PREDICTIONS}. Expected 'id,pred'."
        uid, pred = parts
        assert uid in expected, f"Unexpected id '{uid}' found in {PREDICTIONS}."
        assert uid not in seen, f"Duplicate id '{uid}' found in {PREDICTIONS}."
        assert pred == expected[uid], (
            f"Incorrect prediction for id {uid}. Expected {expected[uid]}, got {pred}."
        )
        assert re.fullmatch(r"-?\d+\.\d{4}", pred), f"Prediction '{pred}' is not formatted to exactly 4 decimal places."
        seen.add(uid)
    assert seen == set(expected)


def write_case(rows, params):
    W1, b1, W2, b2 = params
    with open(DATA, "w") as f:
        f.write("id,v1,v2,v3\n")
        for uid, v1, v2, v3 in rows:
            f.write(f"{uid},{v1:.12g},{v2:.12g},{v3:.12g}\n")

    with open(WEIGHTS, "w") as f:
        f.write("# W1\n")
        for row in W1:
            f.write(" ".join(f"{x:.12g}" for x in row) + "\n")
        f.write("# b1\n")
        f.write(" ".join(f"{x:.12g}" for x in b1) + "\n")
        f.write("# W2\n")
        for x in W2:
            f.write(f"{x:.12g}\n")
        f.write("# b2\n")
        f.write(f"{b2:.12g}\n")


def expected_for(rows, params):
    W1, b1, W2, b2 = params
    result = {}
    for uid, v1, v2, v3 in rows:
        x = [v1 * v1, v1 * v2, math.log(v3)]
        hidden = [max(0.0, b1[j] + sum(x[i] * W1[i][j] for i in range(3))) for j in range(4)]
        z = b2 + sum(hidden[j] * W2[j] for j in range(4))
        pred = 1.0 / (1.0 + math.exp(-z))
        result[str(uid)] = f"{pred:.4f}"
    return result


def random_params(rng):
    W1 = [[rng.uniform(-0.8, 0.8) for _ in range(4)] for _ in range(3)]
    b1 = [rng.uniform(-0.4, 0.4) for _ in range(4)]
    W2 = [rng.uniform(-1.0, 1.0) for _ in range(4)]
    b2 = rng.uniform(-0.5, 0.5)
    return W1, b1, W2, b2


def random_rows(rng, count, first_id):
    return [
        (first_id + i, rng.uniform(-3.5, 3.5), rng.uniform(-3.0, 3.0), math.exp(rng.uniform(-1.8, 2.0)))
        for i in range(count)
    ]


def clear_outputs():
    for path in (PREDICTIONS, BENCHMARK):
        if os.path.exists(path):
            os.remove(path)


def test_complete_pipeline():
    # Preserve the original existence and script-content assertions.
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    with open(SCRIPT, "r") as f:
        script_content = f.read()
    assert "-O3" in script_content, f"Script {SCRIPT} does not seem to compile with '-O3' optimization flag."
    assert os.path.isfile(CPP), f"Source file {CPP} does not exist."

    # Independently compile the submitted C++ source with the required optimization.
    # This prevents a script from substituting CSV files for a real implementation.
    run(["g++", "-std=c++17", "-O3", CPP, "-o", PINNED_BINARY])
    assert os.path.isfile(PINNED_BINARY) and os.access(PINNED_BINARY, os.X_OK)

    # Restore the supplied inputs, execute the requested script, and retain the
    # original fixed-row correctness assertions.
    with open(DATA, "w") as f:
        f.write(CANONICAL_DATA)
    with open(WEIGHTS, "w") as f:
        f.write(CANONICAL_WEIGHTS)
    clear_outputs()
    traced = run(["bash", "-x", SCRIPT])
    trace = traced.stdout + "\n" + traced.stderr
    compile_lines = [line for line in trace.splitlines() if re.search(r"(^|[ /])(g\+\+|c\+\+)( |$)", line)]
    assert any("-O3" in line for line in compile_lines), "run_pipeline.sh did not execute a compiler command with -O3."

    expected_fixed = {"1": "0.5025", "2": "0.5987", "3": "0.5000"}
    assert_predictions(expected_fixed)
    read_benchmark()

    # Secret, non-fixed inputs and weights exercise the submitted C++ binary.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    params1 = random_params(rng)
    rows1 = random_rows(rng, 47, 10000)
    write_case(rows1, params1)
    clear_outputs()
    run([PINNED_BINARY])
    assert_predictions(expected_for(rows1, params1))
    small_time = read_benchmark()

    # Exercise the actual pipeline script on another independently derived case.
    params2 = random_params(rng)
    rows2 = random_rows(rng, 61, 20000)
    write_case(rows2, params2)
    clear_outputs()
    run(["bash", SCRIPT])
    assert_predictions(expected_for(rows2, params2))
    read_benchmark()

    # A much larger complete dataset must affect the measured 1000-pass workload;
    # this rejects constant/zero benchmark files and benchmarks that ignore the data.
    large_rows = random_rows(rng, 5000, 30000)
    write_case(large_rows, params1)
    clear_outputs()
    run([PINNED_BINARY], timeout=180)
    assert_predictions(expected_for(large_rows, params1))
    large_time = read_benchmark()
    assert large_time > 100, "The 1000-pass full-dataset benchmark is implausibly short."
    assert large_time > small_time * 5, (
        "Benchmark time did not scale with a much larger dataset; the benchmark may not cover the entire dataset."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
