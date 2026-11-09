#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shlex
import stat
import subprocess
import tarfile
import tempfile

import pytest

DATASET = "/home/user/data/dataset.csv"
ARCHIVE = "/home/user/raw_data.tar.gz"
OPTIMIZE = "/home/user/optimize.sh"
TRAIN_MODEL = "/home/user/train_model.sh"
BEST_PARAMS = "/home/user/best_params.csv"
THREADS = ["1", "2", "4", "8"]
REGS = ["0.01", "0.1", "1.0", "10.0"]


def archived_dataset_bytes():
    with tarfile.open(ARCHIVE, "r:gz") as archive:
        members = [m for m in archive.getmembers() if m.isfile() and os.path.basename(m.name) == "dataset.csv"]
        assert len(members) == 1, "raw_data.tar.gz must contain exactly one dataset.csv"
        extracted = archive.extractfile(members[0])
        assert extracted is not None
        return extracted.read()


def assert_dataset_matches_archive():
    assert os.path.isfile(DATASET), f"Extracted dataset not found at {DATASET}"
    with open(DATASET, "rb") as f:
        actual = f.read()
    assert actual == archived_dataset_bytes(), "Extracted dataset.csv does not match raw_data.tar.gz"


def parse_best_params(path):
    with open(path, "r") as f:
        raw_lines = f.read().splitlines()
    assert len(raw_lines) == 2, f"Expected exactly 2 lines in {path}, got {len(raw_lines)}"
    assert raw_lines[0] == "threads,reg,error", (
        f"Incorrect header: expected 'threads,reg,error', got '{raw_lines[0]}'"
    )
    values = raw_lines[1].split(",")
    assert len(values) == 3, "Expected 3 comma-separated values in the second line"
    try:
        error = float(values[2])
    except ValueError:
        pytest.fail(f"Error value '{values[2]}' is not a valid float")
    return values[0], values[1], error


def test_dataset_extracted():
    assert_dataset_matches_archive()


def test_optimize_script_exists_and_executable():
    assert os.path.isfile(OPTIMIZE), f"Missing script: {OPTIMIZE}"
    assert os.access(OPTIMIZE, os.X_OK), f"Script is not executable: {OPTIMIZE}"
    with open(OPTIMIZE, "rb") as f:
        first_line = f.readline(256)
    assert first_line.startswith(b"#!") and b"bash" in first_line.lower(), (
        f"{OPTIMIZE} is not an executable Bash script"
    )


def test_best_params_output():
    assert os.path.isfile(BEST_PARAMS), f"Missing output file: {BEST_PARAMS}"
    threads, reg, error = parse_best_params(BEST_PARAMS)
    assert threads == "2", f"Expected optimal threads to be 2, got {threads}"
    assert reg == "0.1", f"Expected optimal regularization to be 0.1, got {reg}"
    assert abs(error - 0.5) < 1e-5, f"Expected minimum error to be approximately 0.5000, got {error}"


def test_z_optimize_executes_full_grid_and_uses_results():
    # Use fresh, verifier-derived errors so a script that merely writes the example
    # answer cannot pass. The instrumented trainer also records both thread variables.
    combinations = [(t, r) for t in THREADS for r in REGS]
    winning_t, winning_r = random.SystemRandom().choice(combinations)
    errors = {}
    for index, combination in enumerate(combinations):
        errors[combination] = 20.0 + index
    errors[(winning_t, winning_r)] = 0.1234

    fd, log_path = tempfile.mkstemp(prefix="optimize-calls-", dir="/tmp")
    os.close(fd)
    os.chmod(log_path, 0o600)

    with open(TRAIN_MODEL, "rb") as f:
        original_train = f.read()
    original_train_mode = stat.S_IMODE(os.stat(TRAIN_MODEL).st_mode)
    original_best = None
    original_best_mode = None
    if os.path.exists(BEST_PARAMS):
        with open(BEST_PARAMS, "rb") as f:
            original_best = f.read()
        original_best_mode = stat.S_IMODE(os.stat(BEST_PARAMS).st_mode)

    cases = []
    for (threads, reg), error in errors.items():
        cases.append(f'  "{threads},{threads},{reg}") printf "%.4f\\n" {error} ;;')

    wrapper = f'''#!/bin/bash
printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "${{OPENBLAS_NUM_THREADS-}}" "${{OMP_NUM_THREADS-}}" "$#" "${{1-}}" "${{2-}}" >> {shlex.quote(log_path)}
if [ "$#" -ne 2 ] || [ "$1" != {shlex.quote(DATASET)} ]; then
    echo "invalid invocation" >&2
    exit 40
fi
case "${{OPENBLAS_NUM_THREADS-}},${{OMP_NUM_THREADS-}},$2" in
{os.linesep.join(cases)}
  *) echo "invalid grid combination or thread environment" >&2; exit 41 ;;
esac
'''

    try:
        with open(TRAIN_MODEL, "w") as f:
            f.write(wrapper)
        os.chmod(TRAIN_MODEL, 0o755)
        if os.path.exists(BEST_PARAMS):
            os.remove(BEST_PARAMS)

        result = subprocess.run(
            [OPTIMIZE],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=45,
        )
        assert result.returncode == 0, (
            f"optimize.sh failed with exit code {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(BEST_PARAMS), "optimize.sh did not create best_params.csv when executed"

        actual_t, actual_r, actual_error = parse_best_params(BEST_PARAMS)
        assert actual_t == winning_t, f"Expected dynamically computed best threads {winning_t}, got {actual_t}"
        assert actual_r == winning_r, f"Expected dynamically computed best regularization {winning_r}, got {actual_r}"
        assert abs(actual_error - errors[(winning_t, winning_r)]) < 1e-5, (
            "best_params.csv does not contain the error returned for the best combination"
        )

        with open(log_path, "r") as f:
            records = [line.rstrip("\n").split("\t") for line in f if line.strip()]
        assert records, "optimize.sh never executed train_model.sh"

        seen = set()
        for record in records:
            assert len(record) == 5, f"Malformed trainer invocation record: {record}"
            openblas, omp, argc, dataset, reg = record
            assert argc == "2", "train_model.sh must be called with exactly two arguments"
            assert dataset == DATASET, f"train_model.sh was called with the wrong dataset: {dataset}"
            assert openblas in THREADS, f"Invalid OPENBLAS_NUM_THREADS value: {openblas}"
            assert omp == openblas, (
                f"OMP_NUM_THREADS ({omp}) did not match OPENBLAS_NUM_THREADS ({openblas})"
            )
            assert reg in REGS, f"Invalid regularization value: {reg}"
            seen.add((openblas, reg))

        assert seen == set(combinations), (
            f"optimize.sh did not execute the complete 16-combination grid; missing {set(combinations) - seen}"
        )
        assert_dataset_matches_archive()
    finally:
        with open(TRAIN_MODEL, "wb") as f:
            f.write(original_train)
        os.chmod(TRAIN_MODEL, original_train_mode)
        if original_best is not None:
            with open(BEST_PARAMS, "wb") as f:
                f.write(original_best)
            os.chmod(BEST_PARAMS, original_best_mode)
        elif os.path.exists(BEST_PARAMS):
            os.remove(BEST_PARAMS)
        try:
            os.remove(log_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
