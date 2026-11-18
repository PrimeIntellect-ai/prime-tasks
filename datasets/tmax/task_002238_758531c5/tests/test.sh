#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST' > /tmp/test_final_state.py
import csv
import glob
import json
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile
import urllib.request

APP = "/home/user/app"
HTTP_URL = "http://127.0.0.1:8080/predict"


def legacy_expected(f1, f2, f3):
    return 5.0 + 1.5 * (2.0 * f1) - 0.8 * (f2 + 10.0) + 3.2 * max(f3, 0.0)


def http_predict(f1, f2, f3):
    body = json.dumps({"f1": f1, "f2": f2, "f3": f3}).encode()
    request = urllib.request.Request(HTTP_URL, data=body, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            raw = response.read().decode()
    except Exception as exc:
        raise AssertionError(f"HTTP request failed: {exc}") from exc
    try:
        decoded = json.loads(raw)
    except Exception as exc:
        raise AssertionError(f"Response is not valid JSON: {raw}") from exc
    assert "prediction" in decoded, f"Missing prediction key: {decoded}"
    prediction = float(decoded["prediction"])
    assert math.isfinite(prediction), f"Non-finite prediction: {prediction}"
    return prediction


def solve(matrix, vector):
    n = len(vector)
    augmented = [list(map(float, matrix[i])) + [float(vector[i])] for i in range(n)]
    for column in range(n):
        pivot = max(range(column, n), key=lambda row: abs(augmented[row][column]))
        assert abs(augmented[pivot][column]) > 1e-12, "Singular ridge system"
        augmented[column], augmented[pivot] = augmented[pivot], augmented[column]
        scale = augmented[column][column]
        augmented[column] = [value / scale for value in augmented[column]]
        for row in range(n):
            if row == column:
                continue
            factor = augmented[row][column]
            augmented[row] = [augmented[row][j] - factor * augmented[column][j] for j in range(n + 1)]
    return [augmented[i][-1] for i in range(n)]


def ridge_fit(rows, lam):
    # Intercept is not regularized; features are the oracle-cleaned values.
    xtx = [[0.0] * 4 for _ in range(4)]
    xty = [0.0] * 4
    for features, target in rows:
        x = [1.0] + features
        for i in range(4):
            xty[i] += x[i] * target
            for j in range(4):
                xtx[i][j] += x[i] * x[j]
    for i in range(1, 4):
        xtx[i][i] += lam
    return solve(xtx, xty)


def predict_weights(weights, cleaned):
    return weights[0] + sum(weights[i + 1] * cleaned[i] for i in range(3))


def load_cleaned_training_data():
    raw_features = []
    targets = []
    with open("/home/user/data/train.csv", newline="") as handle:
        for row in csv.reader(handle):
            assert len(row) == 4
            raw_features.append(tuple(float(value) for value in row[:3]))
            targets.append(float(row[3]))
    oracle_input = "".join(f"{a:.17g},{b:.17g},{c:.17g}\n" for a, b, c in raw_features)
    result = subprocess.run(["/app/clean_oracle"], input=oracle_input, text=True, capture_output=True, timeout=10, check=True)
    cleaned = []
    for line in result.stdout.splitlines():
        values = [float(value) for value in line.split(",")]
        assert len(values) == 3
        cleaned.append(values)
    assert len(cleaned) == len(targets)
    return list(zip(cleaned, targets))


def independently_train():
    rows = load_cleaned_training_data()
    n = len(rows)
    # Sequential 33%, 33%, 34% folds.
    bounds = [(0, n * 33 // 100), (n * 33 // 100, n * 66 // 100), (n * 66 // 100, n)]
    scores = {}
    for lam in (0.1, 1.0, 10.0):
        squared_error = 0.0
        count = 0
        for start, end in bounds:
            training = rows[:start] + rows[end:]
            validation = rows[start:end]
            weights = ridge_fit(training, lam)
            for features, target in validation:
                error = predict_weights(weights, features) - target
                squared_error += error * error
                count += 1
        scores[lam] = squared_error / count
    selected = min(scores, key=scores.get)
    return selected, ridge_fit(rows, selected)


def clean_with_oracle(cases):
    oracle_input = "".join(f"{a:.17g},{b:.17g},{c:.17g}\n" for a, b, c in cases)
    result = subprocess.run(["/app/clean_oracle"], input=oracle_input, text=True, capture_output=True, timeout=10, check=True)
    output = [[float(value) for value in line.split(",")] for line in result.stdout.splitlines()]
    assert len(output) == len(cases)
    return output


def assert_implementation_artifacts():
    assert os.path.isdir(APP), "/home/user/app is missing"
    go_mod = os.path.join(APP, "go.mod")
    assert os.path.isfile(go_mod), "Go module was not initialized in /home/user/app"
    module_text = open(go_mod, errors="replace").read()
    assert "gonum.org/v1/gonum" in module_text, "go.mod does not depend on Gonum"

    files = [path for path in glob.glob(os.path.join(APP, "**", "*.go"), recursive=True)
             if not path.endswith(".pb.go") and not path.endswith("_grpc.pb.go")]
    assert files, "No non-generated Go implementation source found"
    source = "\n".join(open(path, errors="replace").read() for path in files)
    source_no_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)

    assert re.search(r'gonum\.org/v1/gonum/(mat|stat)', source_no_comments), "Implementation does not import a Gonum numerical package"
    assert re.search(r'\b(mat|stat)\.', source_no_comments), "Gonum import is not used by the implementation"
    assert "train.csv" in source_no_comments, "Implementation does not read the training dataset"
    assert re.search(r"clean_oracle|exec\.Command|CommandContext", source_no_comments), "Implementation does not process training or requests through the cleaning oracle"
    assert re.search(r"(?i)(cross.*valid|\bcv\b|fold)", source_no_comments), "No 3-fold cross-validation implementation found"
    assert re.search(r"(?i)(mse|mean.*squared|squared.*error)", source_no_comments), "No MSE evaluation implementation found"

    numbers = [float(token) for token in re.findall(r"(?<![A-Za-z0-9_])(?:\d+\.\d+|\d+)(?![A-Za-z0-9_])", source_no_comments)]
    for required in (0.1, 1.0, 10.0):
        assert any(abs(value - required) < 1e-12 for value in numbers), f"Missing ridge candidate lambda {required}"


def build_grpc_client(tmpdir):
    client = r'''package main
import (
    "context"
    "fmt"
    "os"
    "strconv"
    "time"
    "google.golang.org/grpc"
    "google.golang.org/grpc/credentials/insecure"
)
type PredictRequest struct {
    F1 float64 `protobuf:"fixed64,1,opt,name=f1,proto3" json:"f1,omitempty"`
    F2 float64 `protobuf:"fixed64,2,opt,name=f2,proto3" json:"f2,omitempty"`
    F3 float64 `protobuf:"fixed64,3,opt,name=f3,proto3" json:"f3,omitempty"`
}
func (m *PredictRequest) Reset() { *m = PredictRequest{} }
func (m *PredictRequest) String() string { return fmt.Sprintf("%v,%v,%v", m.F1, m.F2, m.F3) }
func (*PredictRequest) ProtoMessage() {}
type PredictResponse struct {
    Prediction float64 `protobuf:"fixed64,1,opt,name=prediction,proto3" json:"prediction,omitempty"`
}
func (m *PredictResponse) Reset() { *m = PredictResponse{} }
func (m *PredictResponse) String() string { return fmt.Sprintf("%v", m.Prediction) }
func (*PredictResponse) ProtoMessage() {}
func main() {
    if len(os.Args) != 4 { panic("three arguments required") }
    f1, _ := strconv.ParseFloat(os.Args[1], 64)
    f2, _ := strconv.ParseFloat(os.Args[2], 64)
    f3, _ := strconv.ParseFloat(os.Args[3], 64)
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()
    conn, err := grpc.DialContext(ctx, "127.0.0.1:50051", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithBlock())
    if err != nil { panic(err) }
    defer conn.Close()
    out := new(PredictResponse)
    if err := conn.Invoke(ctx, "/Predictor/Predict", &PredictRequest{F1:f1,F2:f2,F3:f3}, out); err != nil { panic(err) }
    fmt.Printf("%.17g", out.Prediction)
}
'''
    open(os.path.join(tmpdir, "main.go"), "w").write(client)
    grpc_version = "v1.56.3"
    app_mod = open(os.path.join(APP, "go.mod"), errors="replace").read()
    match = re.search(r"google\.golang\.org/grpc\s+(v[^\s]+)", app_mod)
    if match:
        grpc_version = match.group(1)
    open(os.path.join(tmpdir, "go.mod"), "w").write(f"module verifiergrpc\n\ngo 1.19\n\nrequire google.golang.org/grpc {grpc_version}\n")
    env = os.environ.copy()
    env["GOTOOLCHAIN"] = "local"
    subprocess.run(["go", "mod", "tidy"], cwd=tmpdir, env=env, check=True, capture_output=True, timeout=180)
    executable = os.path.join(tmpdir, "grpc-client")
    subprocess.run(["go", "build", "-o", executable, "."], cwd=tmpdir, env=env, check=True, capture_output=True, timeout=180)
    return executable


def grpc_predict(executable, case):
    result = subprocess.run([executable] + [format(value, ".17g") for value in case], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f"gRPC invocation failed: {result.stderr}"
    try:
        prediction = float(result.stdout.strip())
    except ValueError as exc:
        raise AssertionError(f"Invalid gRPC prediction: {result.stdout}") from exc
    assert math.isfinite(prediction)
    return prediction


def main():
    assert_implementation_artifacts()

    # Preserve the original fixed HTTP assertions.
    fixed = [(1.0, 2.0, 3.0), (-1.0, -2.0, -3.0), (0.0, 0.0, 0.0), (2.5, -1.5, 4.2)]
    for case in fixed:
        prediction = http_predict(*case)
        expected = legacy_expected(*case)
        assert abs(prediction - expected) < 0.2, f"HTTP prediction {prediction} too far from {expected} for {case}"

    selected_lambda, weights = independently_train()
    assert selected_lambda in (0.1, 1.0, 10.0)

    # Inputs are selected only after the agent has finished, preventing a fixed lookup table.
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    random_cases = [(rng.uniform(-12, 12), rng.uniform(-12, 12), rng.uniform(-12, 12)) for _ in range(24)]
    cleaned = clean_with_oracle(random_cases)
    for case, clean in zip(random_cases, cleaned):
        expected = predict_weights(weights, clean)
        prediction = http_predict(*case)
        assert abs(prediction - expected) < 0.2, f"HTTP prediction {prediction} too far from independently trained model {expected} for {case}"

    # Exercise the actual RPC method; protobuf generation failure is never treated as success.
    with tempfile.TemporaryDirectory() as tmpdir:
        executable = build_grpc_client(tmpdir)
        grpc_cases = [(1.0, 2.0, 3.0)] + random_cases[:7]
        grpc_cleaned = clean_with_oracle(grpc_cases)
        for index, (case, clean) in enumerate(zip(grpc_cases, grpc_cleaned)):
            prediction = grpc_predict(executable, case)
            if index == 0:
                expected = legacy_expected(*case)
            else:
                expected = predict_weights(weights, clean)
            assert abs(prediction - expected) < 0.2, f"gRPC prediction {prediction} too far from {expected} for {case}"


if __name__ == "__main__":
    main()
PYTEST

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
