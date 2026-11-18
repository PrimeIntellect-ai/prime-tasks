#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import stat
import subprocess


def test_predictions_csv_content():
    path = "/home/user/predictions.csv"
    assert os.path.isfile(path), f"Missing predictions file: {path}"

    with open(path, "r") as f:
        content = f.read()

    expected_content = "1,24\n2,27.9\n3,23.6\n"
    lines = [line.strip() for line in content.strip().split("\n")]
    expected_lines = ["1,24", "2,27.9", "3,23.6"]

    assert lines == expected_lines, (
        f"predictions.csv content is incorrect. Expected {expected_lines}, got {lines}"
    )


def test_pipeline_hash_file():
    hash_path = "/home/user/pipeline_hash.txt"
    pred_path = "/home/user/predictions.csv"

    assert os.path.isfile(hash_path), f"Missing hash file: {hash_path}"
    assert os.path.isfile(pred_path), f"Missing predictions file: {pred_path}"

    with open(hash_path, "r") as f:
        actual_hash = f.read().strip()

    with open(pred_path, "rb") as f:
        pred_bytes = f.read()

    expected_hash = hashlib.sha256(pred_bytes).hexdigest()
    assert actual_hash == expected_hash, (
        f"Hash in {hash_path} ({actual_hash}) does not match the actual sha256 "
        f"hash of {pred_path} ({expected_hash})"
    )


def test_pipeline_hash_exact():
    hash_path = "/home/user/pipeline_hash.txt"
    assert os.path.isfile(hash_path), f"Missing hash file: {hash_path}"

    with open(hash_path, "r") as f:
        actual_hash = f.read().strip()

    expected_hash = "165a250325f6e812f8a846f48037f9e0f6cba9c4a8cfba94b0d0c3546a1dfc3a"
    assert actual_hash == expected_hash, (
        f"The hash value is incorrect. Expected {expected_hash}, got {actual_hash}"
    )


def test_repaired_process_script_executes_and_is_reproducible():
    script = "/home/user/process.sh"
    dataset = "/home/user/dataset.csv"
    predictions = "/home/user/predictions.csv"
    hash_path = "/home/user/pipeline_hash.txt"

    assert os.path.exists(script), f"Missing pipeline script: {script}"
    assert stat.S_ISREG(os.stat(script).st_mode), f"Pipeline script is not a regular file: {script}"
    assert os.access(script, os.X_OK), f"Pipeline script is not executable: {script}"

    paths_to_restore = [dataset, predictions, hash_path]
    backups = {}
    for path in paths_to_restore:
        with open(path, "rb") as f:
            backups[path] = f.read()

    def run_pipeline():
        if os.path.lexists(predictions):
            os.unlink(predictions)
        result = subprocess.run(
            [script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, (
            f"process.sh failed with exit code {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(predictions), "process.sh did not create predictions.csv"
        with open(predictions, "rb") as f:
            return f.read()

    try:
        # Rerun the repaired artifact on the instructed dataset.
        canonical = run_pipeline()
        assert canonical == b"1,24\n2,27.9\n3,23.6\n", (
            f"process.sh produced incorrect canonical output: {canonical!r}"
        )

        # Exercise the script on verifier-generated values so a hard-coded output cannot pass.
        rng = random.SystemRandom()
        ids = sorted(rng.sample(range(10, 900), 5), reverse=True)
        rows = []
        expected = []
        for index, row_id in enumerate(ids):
            f1 = rng.randint(5, 30)
            f2 = rng.randint(10, 35)
            f3 = "" if index != 2 else str(rng.randint(1, 9))
            f4 = rng.randint(1, 8)
            rows.append(f"{row_id},{f1},{f2},{f3},{f4}")

            tenths = 5 * f1 + 12 * f2 - 10 * f4
            score = str(tenths // 10) if tenths % 10 == 0 else f"{tenths // 10}.{tenths % 10}"
            expected.append((row_id, f"{row_id},{score}"))

        generated_dataset = ("ID,F1,F2,F3,F4\n" + "\n".join(rows) + "\n").encode()
        expected_bytes = ("\n".join(value for _, value in sorted(expected)) + "\n").encode()

        outputs = []
        for _ in range(3):
            with open(dataset, "wb") as f:
                f.write(generated_dataset)
            outputs.append(run_pipeline())

        assert all(output == expected_bytes for output in outputs), (
            f"process.sh did not compute and numerically sort generated input correctly. "
            f"Expected {expected_bytes!r}, got {outputs!r}"
        )
        assert outputs[0] == outputs[1] == outputs[2], "process.sh output is not reproducible"
    finally:
        for path, data in backups.items():
            with open(path, "wb") as f:
                f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
