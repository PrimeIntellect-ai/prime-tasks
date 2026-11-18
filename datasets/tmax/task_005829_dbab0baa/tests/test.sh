#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import tarfile
import math


def test_script_exists_and_executable():
    script_path = "/home/user/process_sensors.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_processed_sensors_archive():
    archive_path = "/home/user/clean_data_archive.tar.gz"
    processed_dir = "/home/user/processed_sensors"
    raw_dir = "/home/user/raw_sensors"
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist."
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tarball."

    expected_files = sorted(n for n in os.listdir(raw_dir) if n.endswith(".csv"))
    with tarfile.open(archive_path, "r:gz") as tar:
        names = tar.getnames()
        csv_files = [n for n in names if n.endswith(".csv")]
        assert len(csv_files) >= 2, "Archive does not contain the expected CSV files."

        archived = {}
        for member in tar.getmembers():
            if not member.isfile() or not member.name.endswith(".csv"):
                continue
            basename = os.path.basename(member.name)
            assert basename in expected_files, f"Unexpected CSV file in archive: {member.name}"
            assert basename not in archived, f"Duplicate archived CSV filename: {basename}"
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archived file {member.name}"
            archived[basename] = extracted.read()

        assert sorted(archived) == expected_files, "Archive CSV files do not match the processed sensor files."
        for filename in expected_files:
            proc_path = os.path.join(processed_dir, filename)
            assert os.path.isfile(proc_path), f"Processed file {proc_path} is missing."
            with open(proc_path, "rb") as fp:
                assert archived[filename] == fp.read(), f"Archived content differs from {proc_path}."


def get_cleaned_value(val_str):
    if val_str == "NA":
        return 0.0
    val = float(val_str)
    if val > 50.0:
        return 50.0
    if val < -50.0:
        return -50.0
    return val


def test_processed_sensors_data():
    raw_dir = "/home/user/raw_sensors"
    processed_dir = "/home/user/processed_sensors"
    assert os.path.isdir(processed_dir), f"{processed_dir} does not exist."

    raw_files = sorted(n for n in os.listdir(raw_dir) if n.endswith(".csv"))
    processed_files = sorted(n for n in os.listdir(processed_dir) if n.endswith(".csv"))
    assert processed_files == raw_files, "Processed CSV filenames do not exactly match the raw CSV filenames."

    for filename in raw_files:
        raw_path = os.path.join(raw_dir, filename)
        proc_path = os.path.join(processed_dir, filename)
        assert os.path.exists(proc_path), f"Processed file {proc_path} is missing."

        with open(raw_path, 'r', newline='') as fr, open(proc_path, 'r', newline='') as fp:
            raw_reader = csv.DictReader(fr)
            proc_reader = csv.DictReader(fp)

            assert raw_reader.fieldnames == proc_reader.fieldnames, f"Headers mismatch in {filename}"
            raw_rows = list(raw_reader)
            proc_rows = list(proc_reader)
            assert len(proc_rows) == len(raw_rows), f"Row count mismatch in {filename}."

            for raw_row, proc_row in zip(raw_rows, proc_rows):
                assert raw_row['id'] == proc_row['id'], "ID mismatch in processed data."
                for f in ['f1', 'f2', 'f3']:
                    expected_val = get_cleaned_value(raw_row[f])
                    actual_val = float(proc_row[f])
                    assert math.isclose(expected_val, actual_val, rel_tol=1e-5), \
                        f"Value mismatch in {filename} for id {raw_row['id']}, feature {f}. Expected {expected_val}, got {actual_val}"


def test_all_predictions():
    preds_path = "/home/user/all_predictions.csv"
    weights_path = "/home/user/model_weights.txt"
    raw_dir = "/home/user/raw_sensors"

    assert os.path.exists(preds_path), f"{preds_path} does not exist."
    assert os.path.exists(weights_path), f"{weights_path} does not exist."

    with open(weights_path, 'r') as fw:
        w_str = fw.read().strip().split(',')
        w1, w2, w3 = float(w_str[0]), float(w_str[1]), float(w_str[2])

    expected_preds = {}
    for filename in os.listdir(raw_dir):
        if not filename.endswith(".csv"):
            continue
        raw_path = os.path.join(raw_dir, filename)
        with open(raw_path, 'r') as fr:
            reader = csv.DictReader(fr)
            for row in reader:
                id_val = int(row['id'])
                f1 = get_cleaned_value(row['f1'])
                f2 = get_cleaned_value(row['f2'])
                f3 = get_cleaned_value(row['f3'])
                pred = (w1 * f1) + (w2 * f2) + (w3 * f3)
                expected_preds[id_val] = pred

    actual_ids = []
    actual_preds = {}
    with open(preds_path, 'r') as fp:
        reader = csv.reader(fp)
        header = next(reader)
        assert header == ['id', 'prediction'], f"Incorrect header in {preds_path}: {header}"

        for row in reader:
            if not row:
                continue
            id_val = int(row[0])
            pred_val = float(row[1])
            actual_ids.append(id_val)
            actual_preds[id_val] = pred_val

    assert actual_ids == sorted(actual_ids), "Predictions are not sorted by id in ascending order."
    assert len(actual_preds) == len(expected_preds), "Mismatch in total number of predictions."
    for id_val, exp_pred in expected_preds.items():
        assert id_val in actual_preds, f"ID {id_val} missing in predictions."
        assert math.isclose(exp_pred, actual_preds[id_val], rel_tol=1e-4, abs_tol=1e-4), \
            f"Prediction mismatch for ID {id_val}. Expected {exp_pred}, got {actual_preds[id_val]}"


def test_prediction_sum():
    preds_path = "/home/user/all_predictions.csv"
    sum_path = "/home/user/prediction_sum.txt"

    assert os.path.exists(preds_path), f"{preds_path} does not exist."
    assert os.path.exists(sum_path), f"{sum_path} does not exist."

    total_sum = 0.0
    with open(preds_path, 'r') as fp:
        reader = csv.DictReader(fp)
        for row in reader:
            total_sum += float(row['prediction'])

    with open(sum_path, 'r') as fs:
        sum_str = fs.read().strip()

    assert "." in sum_str and len(sum_str.split(".")[1]) == 2, f"Sum {sum_str} is not formatted to 2 decimal places."
    actual_sum = float(sum_str)
    assert math.isclose(total_sum, actual_sum, rel_tol=1e-4, abs_tol=1e-4), \
        f"Prediction sum mismatch. Expected {total_sum:.2f}, got {actual_sum}"
TEST_EOF

# Replace the known inputs with a fresh challenge, remove all prior outputs, and
# require the submitted executable pipeline to regenerate them.
python3 - << 'PREP_EOF' || status=1
import os
import random
import shutil

home = "/home/user"
raw = os.path.join(home, "raw_sensors")
for path in [os.path.join(home, "processed_sensors")]:
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
for name in ["all_predictions.csv", "prediction_sum.txt", "clean_data_archive.tar.gz"]:
    path = os.path.join(home, name)
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
if os.path.lexists(raw):
    if os.path.isdir(raw) and not os.path.islink(raw):
        shutil.rmtree(raw)
    else:
        os.unlink(raw)
os.makedirs(raw)

rng = random.SystemRandom()
ids = rng.sample(range(100, 1000), 8)
normal = lambda: rng.randint(-40, 40)
rows_a = [
    (ids[0], "NA", str(normal()), str(normal())),
    (ids[1], str(rng.randint(51, 150)), str(normal()), "NA"),
    (ids[2], str(rng.randint(-150, -51)), "0", str(normal())),
    (ids[3], str(normal()), str(normal()), str(normal())),
]
rows_b = [
    (ids[4], str(normal()), "NA", str(rng.randint(51, 150))),
    (ids[5], str(normal()), str(rng.randint(-150, -51)), str(normal())),
    (ids[6], "NA", "NA", "NA"),
    (ids[7], str(normal()), str(normal()), str(normal())),
]
for filename, rows in [("sensor_A.csv", rows_a), ("sensor_B.csv", rows_b)]:
    with open(os.path.join(raw, filename), "w", newline="") as f:
        f.write("id,f1,f2,f3\n")
        for row in rows:
            f.write(",".join(map(str, row)) + "\n")

weights = []
while len(weights) < 3:
    value = rng.randint(-3, 3)
    if value != 0:
        weights.append(value)
with open(os.path.join(home, "model_weights.txt"), "w") as f:
    f.write(",".join(map(str, weights)) + "\n")

for root, dirs, files in os.walk(raw):
    os.chown(root, 1000, 1000)
    for name in files:
        os.chown(os.path.join(root, name), 1000, 1000)
os.chown(os.path.join(home, "model_weights.txt"), 1000, 1000)
PREP_EOF

if [ "$status" -eq 0 ]; then
    if [ ! -x /home/user/process_sensors.sh ]; then
        status=1
    else
        runuser -u user -- /home/user/process_sensors.sh || status=1
    fi
fi

if [ "$status" -eq 0 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
