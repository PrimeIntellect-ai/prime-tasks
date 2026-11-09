#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile

VALIDATOR = "/home/user/validator"
SOURCE = "/home/user/validator.c"
DAG = "/home/user/dag_step.sh"
RAW = "/home/user/raw_export.csv"
CLEAN = "/home/user/clean_import.csv"
REJECTED = "/home/user/rejected.csv"

ORIGINAL_VALID = [
    "1,Alice,30,alice@example.com",
    "5,Eve,120,eve@example.com",
    "7,Grace,18,grace@example.com",
]
ORIGINAL_REJECTED = [
    "2,Bob,17,bob@example.com",
    "-3,Charlie,25,charlie@example.com",
    "4,David,45,david.example.com",
    "6,Frank,121,frank@example.com",
    "invalid,Hank,40,hank@example.com",
    "9,Ivy,bad,ivy@example.com",
]


def run_checked(command, **kwargs):
    return subprocess.run(command, check=True, timeout=10, **kwargs)


def generated_case():
    token = secrets.token_hex(8)
    base = secrets.randbelow(800000) + 100000
    records = [
        (f"{base},ValidA{token},18,a{token}@example.test", True),
        (f"{base + 1},ValidB{token},120,b{token}@example.test", True),
        (f"0,Zero{token},44,zero{token}@example.test", False),
        (f"-{base + 2},Negative{token},35,neg{token}@example.test", False),
        (f"not{token},BadId{token},40,id{token}@example.test", False),
        (f"{base + 3},Young{token},17,young{token}@example.test", False),
        (f"{base + 4},Old{token},121,old{token}@example.test", False),
        (f"{base + 5},BadAge{token},age{token},age{token}@example.test", False),
        (f"{base + 6},NoAt{token},67,no-at-{token}.example.test", False),
    ]
    secrets.SystemRandom().shuffle(records)
    input_bytes = b"".join((line + "\n").encode() for line, _ in records)
    valid_bytes = b"".join((line + "\n").encode() for line, valid in records if valid)
    rejected_bytes = b"".join((line + "\n").encode() for line, valid in records if not valid)
    return input_bytes, valid_bytes, rejected_bytes


def assert_validator_behavior(program):
    input_bytes, expected_stdout, expected_stderr = generated_case()
    result = subprocess.run(
        [program], input=input_bytes, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, f"{program} exited with {result.returncode}"
    assert result.stdout == expected_stdout, "Validator did not emit exactly the valid input records to stdout."
    assert result.stderr == expected_stderr, "Validator did not emit exactly the rejected input records to stderr."


def test_validator_executable_exists():
    executable_path = VALIDATOR
    assert os.path.isfile(executable_path), f"Compiled executable {executable_path} does not exist."
    assert os.access(executable_path, os.X_OK), f"{executable_path} is not executable."


def test_validator_source_compiles_and_both_artifacts_work():
    assert os.path.isfile(SOURCE), f"C source {SOURCE} does not exist."
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "validator_from_source")
        result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
        )
        assert result.returncode == 0, "validator.c does not compile with gcc: " + result.stderr.decode(errors="replace")
        assert_validator_behavior(rebuilt)
    assert_validator_behavior(VALIDATOR)


def test_dag_step_script_exists():
    script_path = DAG
    assert os.path.isfile(script_path), f"Bash script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_dag_step_runs_on_provided_export():
    for path in (CLEAN, REJECTED):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    run_checked([DAG], stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_clean_import_csv():
    file_path = CLEAN
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist. Did you run your script?"
    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()
    assert content == ORIGINAL_VALID, "The contents of clean_import.csv do not match the expected valid records."


def test_rejected_csv():
    file_path = REJECTED
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist. Did you run your script?"
    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()
    assert content == ORIGINAL_REJECTED, "The contents of rejected.csv do not match the expected rejected records."


def test_dag_step_invokes_validator_and_routes_dynamic_records():
    input_bytes, expected_clean, expected_rejected = generated_case()
    with open(RAW, "rb") as f:
        original_raw = f.read()

    marker = os.path.join("/tmp", "validator-called-" + secrets.token_hex(12))
    saved_validator = os.path.join("/tmp", "saved-validator-" + secrets.token_hex(12))
    os.replace(VALIDATOR, saved_validator)
    wrapper = "#!/bin/sh\nprintf invoked > " + marker + "\nexec " + saved_validator + " \"$@\"\n"
    with open(VALIDATOR, "w") as f:
        f.write(wrapper)
    os.chmod(VALIDATOR, 0o755)

    try:
        with open(RAW, "wb") as f:
            f.write(input_bytes)
        for path in (CLEAN, REJECTED):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        result = subprocess.run([DAG], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, f"dag_step.sh exited with {result.returncode}"
        assert os.path.isfile(marker), "dag_step.sh did not execute /home/user/validator."
        assert os.path.isfile(CLEAN), "dag_step.sh did not create clean_import.csv."
        assert os.path.isfile(REJECTED), "dag_step.sh did not create rejected.csv."
        with open(CLEAN, "rb") as f:
            assert f.read() == expected_clean, "dag_step.sh did not route validator stdout to clean_import.csv."
        with open(REJECTED, "rb") as f:
            assert f.read() == expected_rejected, "dag_step.sh did not route validator stderr to rejected.csv."
    finally:
        try:
            os.remove(VALIDATOR)
        except FileNotFoundError:
            pass
        os.replace(saved_validator, VALIDATOR)
        with open(RAW, "wb") as f:
            f.write(original_raw)
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
        subprocess.run([DAG], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
