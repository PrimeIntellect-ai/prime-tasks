#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import shutil
import subprocess
import tempfile
from collections import Counter

SCRIPT_PATH = "/home/user/build_dataset.sh"
DATA_PATH = "/home/user/data"
VALUES_PATH = "/home/user/singular_values.txt"
LABEL_PATH = "/home/user/training_label.txt"


def fixture_files():
    return sorted(
        os.path.join(DATA_PATH, name)
        for name in os.listdir(DATA_PATH)
        if name.startswith("traj_") and name.endswith(".dat")
    )


def expected_from_fixture():
    """Reproduce the installed script's awk rounding from the actual fixture."""
    values = []
    env = os.environ.copy()
    env["LC_ALL"] = "C"

    for path in fixture_files():
        tail = subprocess.run(
            ["tail", "-n", "1", path],
            check=True,
            stdout=subprocess.PIPE,
            env=env,
        ).stdout
        value = subprocess.run(
            ["/usr/bin/awk", "{print $2 * 0.987}"],
            input=tail,
            check=True,
            stdout=subprocess.PIPE,
            env=env,
        ).stdout.decode().strip()
        values.append(value)

    sorted_values = subprocess.run(
        ["sort", "-n"],
        input=("\n".join(values) + "\n").encode(),
        check=True,
        stdout=subprocess.PIPE,
        env=env,
    ).stdout
    label = subprocess.run(
        [
            "/usr/bin/awk",
            '{ dist += ($1 - (NR*0.5))^2 } END { printf "%.6f\\n", dist }',
        ],
        input=sorted_values,
        check=True,
        stdout=subprocess.PIPE,
        env=env,
    ).stdout.decode().strip()
    return values, label


def run_script():
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}:\n{result.stderr}"
    )


def assert_outputs(expected_values, expected_label):
    assert os.path.isfile(VALUES_PATH), f"File {VALUES_PATH} does not exist."
    with open(VALUES_PATH, "r") as f:
        actual_values = [line.strip() for line in f if line.strip()]
    assert Counter(actual_values) == Counter(expected_values), (
        "singular_values.txt was not produced by correctly extracting every trajectory"
    )

    assert os.path.isfile(LABEL_PATH), f"File {LABEL_PATH} does not exist. Did you run the script?"
    with open(LABEL_PATH, "r") as f:
        content = f.read().strip()
    assert content == expected_label, (
        f"Expected training_label.txt to contain {expected_label}, but found {content}."
    )
    return content


def test_script_executes_pipeline_reproducibly():
    """Exercise the submitted script on independently chosen trajectory values."""
    backup_root = tempfile.mkdtemp(prefix="trajectory_backup_")
    backup_data = os.path.join(backup_root, "data")
    shutil.copytree(DATA_PATH, backup_data)

    try:
        for i in range(1, 101):
            whole = (i * 37) % 101
            fraction = 123456 + i
            with open(os.path.join(DATA_PATH, f"traj_{i}.dat"), "w") as f:
                f.write("0.0 0.0\n")
                f.write(f"1.0 {whole}.{fraction:06d}\n")

        expected_values, expected_label = expected_from_fixture()
        observed = []
        for _ in range(2):
            run_script()
            observed.append(assert_outputs(expected_values, expected_label))
        assert observed[0] == observed[1], "Repeated script runs produced different labels."
    finally:
        shutil.rmtree(DATA_PATH, ignore_errors=True)
        shutil.copytree(backup_data, DATA_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)
        # Leave the required label generated from the original installed fixture.
        run_script()


def test_training_label_correct():
    """Test against the rounded values actually created by the installed fixture."""
    expected_values, expected_str = expected_from_fixture()
    assert_outputs(expected_values, expected_str)


def test_script_modifications():
    """Test that the script was modified correctly to include sorting and keep parallelization."""
    script_path = "/home/user/build_dataset.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {script_path} is no longer executable."

    with open(script_path, "r") as f:
        content = f.read()

    assert "xargs" in content and "-P" in content, "Parallel extraction logic (xargs -P) was removed or altered."
    assert "sort" in content, "The script does not seem to contain 'sort' to order the values."
    assert "awk" in content and "dist +=" in content, "The awk calculation logic was removed or altered."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
