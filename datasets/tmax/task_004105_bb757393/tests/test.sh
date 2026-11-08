#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

SCRIPT_PATH = Path("/home/user/run_experiment.sh")
LOG_PATH = Path("/home/user/experiment_log.txt")
DATASET_DIR = Path("/home/user/datasets")


def test_run_experiment_script_exists_and_executable():
    """Test that the run_experiment.sh script exists and is executable."""
    script_path = "/home/user/run_experiment.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_experiment_log_exists():
    """Test that the experiment_log.txt file exists."""
    log_path = "/home/user/experiment_log.txt"
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."


def test_experiment_log_content():
    """Test that the experiment_log.txt contains the correct results."""
    log_path = "/home/user/experiment_log.txt"
    if not os.path.isfile(log_path):
        return  # Handled by previous test

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "invalid_chars.csv:INVALID_SCHEMA",
        "invalid_cols.csv:INVALID_SCHEMA",
        "invalid_floats.csv:INVALID_SCHEMA",
        "valid_1.csv:-16",
        "valid_na.csv:36"
    ]
    expected_content = "\n".join(expected_lines)

    assert content == expected_content, (
        f"The content of {log_path} is incorrect.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content}"
    )


def test_script_is_bash_and_processes_dynamic_datasets_on_each_run():
    first_line = SCRIPT_PATH.open("rb").readline()
    assert first_line.startswith(b"#!") and b"bash" in first_line, (
        "run_experiment.sh must be an executable Bash script"
    )

    def positive():
        return secrets.randbelow(90) + 1

    def write_suite(round_number):
        for path in DATASET_DIR.glob("*.csv"):
            path.unlink()
        for path in DATASET_DIR.glob("verifier_ignore_*.txt"):
            path.unlink()

        token = secrets.token_hex(8)
        expected = {}

        def add_valid(prefix, rows):
            name = f"{prefix}_{token}.csv"
            text_rows = []
            total = 0
            for left, right in rows:
                text_rows.append(
                    f"{'NA' if left is None else left},{'NA' if right is None else right}"
                )
                total += (0 if left is None else left) * (0 if right is None else right)
            (DATASET_DIR / name).write_text("\n".join(text_rows) + "\n")
            expected[name] = str(total)

        p = positive() + round_number
        q = positive() + round_number
        r = positive() + round_number
        add_valid("alpha_valid", [(p, q), (-r, p), (q, -r), (0, q)])
        add_valid("beta_na", [(None, q), (-p, None), (r, q), (None, None)])
        add_valid("gamma_negative", [(-p, -q), (-r, q), (p, -r)])

        invalid_files = {
            f"delta_columns_{token}.csv": f"{p},{q},{r}\n{q},{r}\n",
            f"epsilon_chars_{token}.csv": f"{p},{q}\n{r},word\n",
            f"eta_float_{token}.csv": f"{p}.5,{q}\n{r},{p}\n",
            f"theta_missing_{token}.csv": f"{p},\n{q},{r}\n",
            f"zeta_wrong_na_{token}.csv": f"na,{q}\n{r},{p}\n",
        }
        for name, content in invalid_files.items():
            (DATASET_DIR / name).write_text(content)
            expected[name] = "INVALID_SCHEMA"

        (DATASET_DIR / f"verifier_ignore_{token}.txt").write_text("1,2\n")
        return "\n".join(f"{name}:{expected[name]}" for name in sorted(expected))

    for round_number in (1, 2):
        expected_content = write_suite(round_number)
        if LOG_PATH.exists() or LOG_PATH.is_symlink():
            LOG_PATH.unlink()

        try:
            completed = subprocess.run(
                [str(SCRIPT_PATH)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise AssertionError(f"Could not execute run_experiment.sh: {exc}") from exc

        assert LOG_PATH.is_file(), (
            "Executing run_experiment.sh did not create /home/user/experiment_log.txt. "
            f"stdout={completed.stdout!r}, stderr={completed.stderr!r}"
        )
        actual_content = LOG_PATH.read_text().strip()
        assert actual_content == expected_content, (
            f"Dynamic dataset round {round_number} was processed incorrectly.\n"
            f"Expected:\n{expected_content}\n"
            f"Got:\n{actual_content}\n"
            f"stdout={completed.stdout!r}\n"
            f"stderr={completed.stderr!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
