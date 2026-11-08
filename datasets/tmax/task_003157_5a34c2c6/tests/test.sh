#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

SCRIPT = "/home/user/process_data.sh"
RAW = "/home/user/raw_data.csv"
OUTPUT = "/home/user/processed_data.csv"

ORIGINAL_RAW = """record_id,dataset_split,val_x,val_y
1,train,10,4
2,train,20,NA
3,train,-5,30
4,train,20,8
5,test,15,10
6,test,25,12
7,train,30,12
8,test,,22
"""

ORIGINAL_EXPECTED = """record_id,dataset_split,norm_x,norm_y
1,train,-1.2247,-1.2247
4,train,0.0000,0.0000
5,test,-0.6124,0.6124
6,test,0.6124,1.2247
7,train,1.2247,1.2247"""


def normalized_text(path):
    with open(path, "r") as f:
        return f.read().replace("\r\n", "\n").strip()


def test_processed_data_exists_and_content():
    expected_file = OUTPUT
    assert os.path.exists(expected_file), f"Output file {expected_file} is missing."
    assert os.path.isfile(expected_file), f"Output path {expected_file} is not a file."

    actual_content = normalized_text(expected_file)
    expected_content = ORIGINAL_EXPECTED.replace("\r\n", "\n").strip()

    assert actual_content == expected_content, (
        f"Content of {expected_file} does not match the expected processed data.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


def test_script_exists():
    script_file = SCRIPT
    assert os.path.exists(script_file), f"Script file {script_file} is missing."
    assert os.path.isfile(script_file), f"Script path {script_file} is not a file."


def reference_output(rows):
    valid = []
    for row in rows:
        record_id, split, val_x, val_y = row
        if val_x == "" or val_y == "" or val_y in ("NA", "NULL"):
            continue
        x = float(val_x)
        y = float(val_y)
        if x < 0:
            continue
        valid.append((int(record_id), split, x, y))

    train = [row for row in valid if row[1] == "train"]
    assert train
    mean_x = sum(row[2] for row in train) / len(train)
    mean_y = sum(row[3] for row in train) / len(train)
    std_x = math.sqrt(sum((row[2] - mean_x) ** 2 for row in train) / len(train))
    std_y = math.sqrt(sum((row[3] - mean_y) ** 2 for row in train) / len(train))
    assert std_x > 0 and std_y > 0

    lines = ["record_id,dataset_split,norm_x,norm_y"]
    for record_id, split, x, y in sorted(valid, key=lambda row: row[0]):
        lines.append(
            f"{record_id},{split},{(x - mean_x) / std_x:.4f},{(y - mean_y) / std_y:.4f}"
        )
    return "\n".join(lines)


def run_script(rows):
    raw_content = "record_id,dataset_split,val_x,val_y\n" + "\n".join(
        ",".join(row) for row in rows
    ) + "\n"
    with open(RAW, "w") as f:
        f.write(raw_content)

    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        ["/bin/bash", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"process_data.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT), "process_data.sh did not generate processed_data.csv"
    assert os.path.isfile(OUTPUT), "processed_data.csv is not a regular file"

    expected = reference_output(rows)
    actual = normalized_text(OUTPUT)
    assert actual == expected, (
        f"Pipeline output was incorrect for a generated input.\n"
        f"Expected:\n{expected}\n\nActual:\n{actual}"
    )


def generated_rows():
    rng = secrets.SystemRandom()
    ids = rng.sample(range(100, 10000), 11)
    base_x = rng.randrange(20, 300)
    base_y = rng.randrange(20, 300)
    x_offsets = sorted(rng.sample(range(1, 100), 4))
    y_offsets = sorted(rng.sample(range(1, 100), 4))

    rows = [
        (str(ids[0]), "train", str(base_x + x_offsets[0]), str(base_y + y_offsets[0])),
        (str(ids[1]), "train", str(base_x + x_offsets[1]), str(base_y + y_offsets[1])),
        (str(ids[2]), "train", str(base_x + x_offsets[2]), str(base_y + y_offsets[2])),
        (str(ids[3]), "train", str(base_x + x_offsets[3]), str(base_y + y_offsets[3])),
        (str(ids[4]), "test", str(base_x + rng.randrange(120, 250)), str(base_y + rng.randrange(120, 250))),
        (str(ids[5]), "test", str(base_x + rng.randrange(1, 100)), str(base_y + rng.randrange(1, 100))),
        (str(ids[6]), "train", str(-rng.randrange(1, 50)), str(base_y + 10)),
        (str(ids[7]), "train", str(base_x + 10), "NA"),
        (str(ids[8]), "test", "", str(base_y + 20)),
        (str(ids[9]), "test", str(base_x + 20), "NULL"),
        (str(ids[10]), "test", str(base_x + 30), ""),
    ]
    rng.shuffle(rows)
    return rows


def test_script_executes_pipeline_on_generated_inputs():
    try:
        for _ in range(3):
            run_script(generated_rows())

        with open(RAW, "w") as f:
            f.write(ORIGINAL_RAW)
        if os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        result = subprocess.run(
            ["/bin/bash", SCRIPT], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(OUTPUT)
        assert normalized_text(OUTPUT) == ORIGINAL_EXPECTED
    finally:
        with open(RAW, "w") as f:
            f.write(ORIGINAL_RAW)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
