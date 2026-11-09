#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import stat
import subprocess
import tempfile

MODEL_C = "/home/user/src/model.c"
MODEL = "/home/user/src/model"
PIPELINE = "/home/user/pipeline.sh"
FEATURES = "/home/user/data/features.csv"
LABELS = "/home/user/data/labels.csv"
ACCURACY = "/home/user/accuracy.txt"


def expected_accuracy(features_path=FEATURES, labels_path=LABELS):
    predictions = {}
    with open(features_path, newline="") as f:
        for row in csv.DictReader(f):
            score = float(row["x"]) * 0.5 + float(row["y"]) * 0.3 + float(row["z"]) * 0.2
            predictions[row["id"]] = 1 if score > 0.5 else 0

    labels = {}
    with open(labels_path, newline="") as f:
        for row in csv.DictReader(f):
            labels[row["id"]] = int(row["label"])

    compared = [(prediction, labels[fid]) for fid, prediction in predictions.items() if fid in labels]
    matches = sum(prediction == label for prediction, label in compared)
    percentage = matches / len(compared) * 100 if compared else 0.0
    return f"Accuracy: {percentage:.2f}%"


def run(command, timeout=20, env=None):
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
        env=env,
    )


def test_01_model_c_exists():
    assert os.path.isfile(MODEL_C), f"File {MODEL_C} is missing."


def test_02_pipeline_sh_exists_and_executable():
    assert os.path.isfile(PIPELINE), f"File {PIPELINE} is missing."
    assert os.access(PIPELINE, os.X_OK), f"File {PIPELINE} is not executable."


def test_03_accuracy_txt_content():
    assert os.path.isfile(ACCURACY), f"File {ACCURACY} is missing."

    if os.path.isfile(FEATURES) and os.path.isfile(LABELS):
        try:
            expected_text = expected_accuracy()
        except (ValueError, KeyError, csv.Error):
            expected_text = "Accuracy: 90.00%"
    else:
        expected_text = "Accuracy: 90.00%"

    with open(ACCURACY) as f:
        content = f.read().strip()
    assert content == expected_text, f"Expected '{expected_text}' in {ACCURACY}, but got '{content}'."


def test_04_compile_and_execute_model_on_independent_input():
    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "model")
        input_csv = os.path.join(td, "features.csv")
        with open(input_csv, "w") as f:
            f.write(
                "id,x,y,z\n"
                "21,0,0,0\n"
                "22,1,0,0\n"
                "23,1.0002,0,0\n"
                "24,0,1,1\n"
                "25,0.2,0.5,1\n"
                "26,0.4,0.4,1\n"
            )

        run(["gcc", "-O3", MODEL_C, "-o", executable])
        result = run([executable, input_csv])
        rows = list(csv.reader(result.stdout.splitlines()))
        assert rows == [
            ["id", "prediction"],
            ["21", "0"],
            ["22", "0"],
            ["23", "1"],
            ["24", "0"],
            ["25", "0"],
            ["26", "1"],
        ], f"Unexpected model output: {result.stdout!r}"


def test_05_pipeline_runs_successfully_on_supplied_data():
    if os.path.exists(MODEL):
        os.remove(MODEL)
    if os.path.exists(ACCURACY):
        os.remove(ACCURACY)

    run([PIPELINE])

    assert os.path.isfile(MODEL), "pipeline.sh did not create /home/user/src/model"
    assert os.access(MODEL, os.X_OK), "The compiled model is not executable"
    assert os.path.isfile(ACCURACY), "pipeline.sh did not create accuracy.txt"
    with open(ACCURACY) as f:
        actual = f.read().strip()
    assert actual == expected_accuracy(), f"Pipeline produced incorrect accuracy: {actual!r}"


def test_06_pipeline_compiles_and_executes_the_model_for_predictions():
    paths = [MODEL_C, FEATURES, LABELS, MODEL, ACCURACY]
    saved = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                saved[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
        else:
            saved[path] = None

    marker = "/tmp/pipeline_model_executed"
    sentinel_source = r'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    FILE *in = fopen(argv[1], "r");
    if (!in) return 3;
    FILE *marker = fopen("/tmp/pipeline_model_executed", "w");
    if (!marker) return 4;
    fputs("executed\n", marker);
    fclose(marker);

    char line[1024];
    if (!fgets(line, sizeof(line), in)) return 5;
    puts("id,prediction");
    while (fgets(line, sizeof(line), in)) {
        char *comma = strchr(line, ',');
        if (!comma) continue;
        *comma = '\0';
        int id = atoi(line);
        printf("%s,%d\n", line, (id == 101 || id == 103) ? 1 : 0);
    }
    fclose(in);
    return 0;
}
'''

    try:
        if os.path.exists(marker):
            os.remove(marker)
        with open(MODEL_C, "w") as f:
            f.write(sentinel_source)
        with open(FEATURES, "w") as f:
            f.write("id,x,y,z\n101,0,0,0\n102,0,0,0\n103,0,0,0\n")
        with open(LABELS, "w") as f:
            f.write("id,label\n101,1\n102,0\n103,1\n")
        if os.path.exists(MODEL):
            os.remove(MODEL)
        if os.path.exists(ACCURACY):
            os.remove(ACCURACY)

        run([PIPELINE])

        assert os.path.isfile(MODEL), "pipeline.sh did not compile model.c"
        assert os.access(MODEL, os.X_OK), "pipeline.sh did not produce an executable model"
        assert os.path.isfile(marker), "pipeline.sh did not execute the compiled model"
        assert os.path.isfile(ACCURACY), "pipeline.sh did not write accuracy.txt"
        with open(ACCURACY) as f:
            actual = f.read().strip()
        assert actual == "Accuracy: 100.00%", f"Pipeline did not evaluate the model predictions: {actual!r}"
    finally:
        for path, value in saved.items():
            if value is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                data, mode = value
                with open(path, "wb") as f:
                    f.write(data)
                os.chmod(path, mode)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
