#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR=$(mktemp -d)
for name in dataset.csv centered_data.csv metrics.log; do
    if [ -e "/home/user/$name" ]; then
        cp -a "/home/user/$name" "$BACKUP_DIR/$name"
        touch "$BACKUP_DIR/$name.present"
    fi
done

cleanup() {
    for name in dataset.csv centered_data.csv metrics.log; do
        rm -f "/home/user/$name"
        if [ -e "$BACKUP_DIR/$name.present" ]; then
            cp -a "$BACKUP_DIR/$name" "/home/user/$name"
        fi
    done
    rm -rf "$BACKUP_DIR"
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_preprocess_script_exists_and_executable():
    """Test that preprocess.sh exists and is executable."""
    script_path = "/home/user/preprocess.sh"
    assert os.path.isfile(script_path), f"Script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_centered_data_correctness():
    """Test that centered_data.csv is correctly mean-centered and formatted to 2 decimal places."""
    dataset_path = "/home/user/dataset.csv"
    centered_path = "/home/user/centered_data.csv"

    assert os.path.isfile(dataset_path), f"Original dataset missing: {dataset_path}"
    assert os.path.isfile(centered_path), f"Centered data missing: {centered_path}"

    with open(dataset_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    data = [[float(x) for x in line.split(",")] for line in lines]
    n = len(data)
    means = [sum(col) / n for col in zip(*data)]

    expected_centered = []
    for row in data:
        expected_centered.append(",".join(f"{val - mean:.2f}" for val, mean in zip(row, means)))

    with open(centered_path, "r") as f:
        actual_centered = [line.strip() for line in f if line.strip()]

    assert actual_centered == expected_centered, "The contents of centered_data.csv do not match the expected mean-centered values."


def test_metrics_log_correctness():
    """Test that metrics.log contains the correct mean values formatted to 2 decimal places."""
    dataset_path = "/home/user/dataset.csv"
    log_path = "/home/user/metrics.log"

    assert os.path.isfile(dataset_path), f"Original dataset missing: {dataset_path}"
    assert os.path.isfile(log_path), f"Metrics log missing: {log_path}"

    with open(dataset_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    data = [[float(x) for x in line.split(",")] for line in lines]
    n = len(data)
    means = [sum(col) / n for col in zip(*data)]

    expected_log_entry = f"Col1_mean={means[0]:.2f}, Col2_mean={means[1]:.2f}, Col3_mean={means[2]:.2f}"

    with open(log_path, "r") as f:
        log_content = f.read()

    assert expected_log_entry in log_content, f"Expected log entry '{expected_log_entry}' not found in {log_path}."


def test_script_processes_changed_inputs_and_appends_log():
    """Execute the submitted artifact on unpredictable datasets and verify its behavior."""
    rng = secrets.SystemRandom()

    for case in range(2):
        data = [[rng.randint(-900, 900) for _ in range(3)] for _ in range(4)]
        # Ensure every column has variation, independent of an unlikely random collision.
        for col in range(3):
            data[col + 1][col] += 17 + case + col

        with open("/home/user/dataset.csv", "w") as f:
            for row in data:
                f.write(",".join(str(value) for value in row) + "\n")

        sentinel = f"existing-log-entry-{case}"
        with open("/home/user/metrics.log", "w") as f:
            f.write(sentinel + "\n")
        try:
            os.remove("/home/user/centered_data.csv")
        except FileNotFoundError:
            pass

        result = subprocess.run(
            ["/home/user/preprocess.sh"],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"preprocess.sh failed on changed input with exit code {result.returncode}: "
            f"{result.stderr}"
        )

        means = [sum(row[col] for row in data) / len(data) for col in range(3)]
        expected_centered = [
            ",".join(f"{row[col] - means[col]:.2f}" for col in range(3))
            for row in data
        ]
        assert os.path.isfile("/home/user/centered_data.csv"), "Script did not create centered_data.csv"
        with open("/home/user/centered_data.csv") as f:
            actual_centered = [line.strip() for line in f if line.strip()]
        assert actual_centered == expected_centered, "Script produced incorrect output for a changed dataset"

        expected_log = (
            f"Col1_mean={means[0]:.2f}, Col2_mean={means[1]:.2f}, "
            f"Col3_mean={means[2]:.2f}"
        )
        with open("/home/user/metrics.log") as f:
            actual_log_lines = f.read().splitlines()
        assert actual_log_lines == [sentinel, expected_log], (
            "Script did not append exactly the required metrics entry"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
