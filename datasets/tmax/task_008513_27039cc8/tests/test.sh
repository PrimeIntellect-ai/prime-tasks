#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'REF_EOF' > /tmp/strict_reference.go
package main

import (
    "fmt"
    "math/rand"
    "os"
    "strconv"

    "gonum.org/v1/gonum/mat"
    "gonum.org/v1/gonum/stat"
)

func main() {
    seed, err := strconv.ParseInt(os.Args[1], 10, 64)
    if err != nil {
        panic(err)
    }
    rand.Seed(seed)

    numSamples := 100
    numFeatures := 10
    targetDim := 3
    trainSamples := 80
    testSamples := 20

    XData := make([]float64, numSamples*numFeatures)
    YData := make([]float64, numSamples)
    for i := 0; i < numSamples; i++ {
        for j := 0; j < numFeatures; j++ {
            XData[i*numFeatures+j] = rand.NormFloat64()
        }
        YData[i] = 2.0*XData[i*numFeatures] - 1.5*XData[i*numFeatures+1] + rand.NormFloat64()*0.5
    }

    X := mat.NewDense(numSamples, numFeatures, XData)
    Y := mat.NewVecDense(numSamples, YData)

    means := make([]float64, numFeatures)
    for j := 0; j < numFeatures; j++ {
        col := mat.Col(nil, j, X.Slice(0, trainSamples, 0, numFeatures))
        means[j] = stat.Mean(col, nil)
    }

    XTrainCentered := mat.NewDense(trainSamples, numFeatures, nil)
    XTestCentered := mat.NewDense(testSamples, numFeatures, nil)
    for i := 0; i < trainSamples; i++ {
        for j := 0; j < numFeatures; j++ {
            XTrainCentered.Set(i, j, X.At(i, j)-means[j])
        }
    }
    for i := 0; i < testSamples; i++ {
        for j := 0; j < numFeatures; j++ {
            XTestCentered.Set(i, j, X.At(trainSamples+i, j)-means[j])
        }
    }

    var svd mat.SVD
    if !svd.Factorize(XTrainCentered, mat.SVDThin) {
        panic("SVD failed")
    }
    var V mat.Dense
    svd.VTo(&V)
    P := V.Slice(0, numFeatures, 0, targetDim)

    XTrain := mat.NewDense(trainSamples, targetDim, nil)
    XTrain.Mul(XTrainCentered, P)
    XTest := mat.NewDense(testSamples, targetDim, nil)
    XTest.Mul(XTestCentered, P)
    YTrain := Y.SliceVec(0, trainSamples)
    YTest := Y.SliceVec(trainSamples, numSamples)

    var XTrainT mat.Dense
    XTrainT.CloneFrom(XTrain.T())
    var XTX mat.Dense
    XTX.Mul(&XTrainT, XTrain)
    var XTXInv mat.Dense
    if err := XTXInv.Inverse(&XTX); err != nil {
        panic(err)
    }
    var XTY mat.VecDense
    XTY.MulVec(&XTrainT, YTrain)
    var w mat.VecDense
    w.MulVec(&XTXInv, &XTY)
    var YPred mat.VecDense
    YPred.MulVec(XTest, &w)

    var mse float64
    for i := 0; i < testSamples; i++ {
        d := YTest.AtVec(i) - YPred.AtVec(i)
        mse += d * d
    }
    mse /= float64(testSamples)
    fmt.Printf("%f\n", mse)
}
REF_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import subprocess
import tempfile

import pytest

PIPELINE = "/home/user/ml_pipeline"
MAIN = os.path.join(PIPELINE, "main.go")
RESULTS = "/home/user/experiment_results.json"
FLOAT_OUTPUT = re.compile(r"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")


def run_go(directory, filename="main.go", args=()):
    proc = subprocess.run(
        ["go", "run", filename, *map(str, args)],
        cwd=directory,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=90,
    )
    assert proc.returncode == 0, f"Go program failed to compile or run:\n{proc.stderr}"
    output = proc.stdout.strip()
    assert FLOAT_OUTPUT.fullmatch(output), f"Expected exactly one numeric MSE on stdout, got: {proc.stdout!r}"
    return float(output)


def make_module(source_name, source_text):
    directory = tempfile.mkdtemp(prefix="ml_pipeline_verify_")
    with open(os.path.join(directory, source_name), "w") as f:
        f.write(source_text)
    for name in ("go.mod", "go.sum"):
        src = os.path.join(PIPELINE, name)
        assert os.path.isfile(src), f"Required module file {src} is missing"
        shutil.copy2(src, os.path.join(directory, name))
    return directory


def strict_reference(seed):
    with open("/tmp/strict_reference.go") as f:
        source = f.read()
    directory = make_module("reference.go", source)
    try:
        return run_go(directory, "reference.go", (seed,))
    finally:
        shutil.rmtree(directory)


def load_results():
    with open(RESULTS, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS} is not valid JSON.")


def test_experiment_results_exists():
    assert os.path.isfile(RESULTS), f"File {RESULTS} does not exist. Did you create the experiment tracking file?"


def test_experiment_results_content():
    data = load_results()
    assert "leaky_mse" in data, "Key 'leaky_mse' is missing from experiment_results.json"
    assert "strict_mse" in data, "Key 'strict_mse' is missing from experiment_results.json"

    leaky_mse = data["leaky_mse"]
    strict_mse = data["strict_mse"]
    assert isinstance(leaky_mse, float), "Value for 'leaky_mse' must be a float."
    assert isinstance(strict_mse, float), "Value for 'strict_mse' must be a float."

    expected_leaky = 0.323568
    expected_strict = 0.385718
    epsilon = 1e-4
    assert abs(leaky_mse - expected_leaky) < epsilon, f"Expected leaky_mse to be near {expected_leaky}, but got {leaky_mse}"
    assert abs(strict_mse - expected_strict) < epsilon, f"Expected strict_mse to be near {expected_strict}, but got {strict_mse}"


def test_main_go_exists_and_modified():
    assert os.path.isfile(MAIN), f"File {MAIN} does not exist."
    with open(MAIN, "r") as f:
        content = f.read()
    assert "gonum.org/v1/gonum/mat" in content, "The modified main.go is missing the gonum matrix library import."


def test_submitted_program_compiles_runs_and_matches_tracking_file():
    actual = run_go(PIPELINE)
    expected = strict_reference(42)
    assert actual == expected, f"Program printed {actual}, but training-only PCA produces {expected}"
    assert load_results()["strict_mse"] == actual, "strict_mse must exactly equal the output of the fixed program"


def test_pca_behavior_uses_training_data_only_for_other_datasets():
    with open(MAIN, "r") as f:
        source = f.read()

    seed_pattern = re.compile(r"rand\.Seed\(\s*[+-]?\d+\s*\)")
    assert seed_pattern.search(source), "The deterministic rand.Seed call from the supplied pipeline is missing"

    for seed in random.SystemRandom().sample(range(1000, 2_000_000_000), 2):
        variant, count = seed_pattern.subn(f"rand.Seed({seed})", source, count=1)
        assert count == 1
        directory = make_module("main.go", variant)
        try:
            actual = run_go(directory)
        finally:
            shutil.rmtree(directory)
        expected = strict_reference(seed)
        assert actual == expected, (
            f"For generated dataset seed {seed}, program printed {actual}; "
            f"training-only means and PCA produce {expected}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
