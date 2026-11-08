#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import shutil
import stat
import subprocess
import tempfile

import pytest

LEGACY = "/app/legacy_cleaner"
GO_CLEANER = "/home/user/go_cleaner"
GO_SOURCE = "/home/user/cleaner.go"


def file_hash(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.digest()


def generated_inputs():
    random.seed(42)
    cases = []
    for _ in range(100):
        num_floats = random.randint(1, 100)
        floats = [random.uniform(-10000.0, 10000.0) for _ in range(num_floats)]
        cases.append(" ".join(f"{f:.6f}" for f in floats) + "\n")
    return cases


def run_program(path, input_str):
    proc = subprocess.run(
        [path],
        input=input_str,
        text=True,
        capture_output=True,
        check=True,
        timeout=10,
    )
    return proc.stdout.strip()


def run_isolated(path, input_str):
    """Run a static executable in a chroot containing no legacy cleaner."""
    with tempfile.TemporaryDirectory(prefix="cleaner-root-") as root:
        os.chmod(root, 0o755)
        isolated_exe = os.path.join(root, "cleaner")
        shutil.copyfile(path, isolated_exe)
        os.chmod(isolated_exe, 0o555)

        def enter_chroot():
            os.chroot(root)
            os.chdir("/")
            os.setgroups([])
            os.setgid(65534)
            os.setuid(65534)

        proc = subprocess.run(
            ["/cleaner"],
            input=input_str,
            text=True,
            capture_output=True,
            check=True,
            timeout=10,
            preexec_fn=enter_chroot,
        )
        return proc.stdout.strip()


@pytest.fixture(scope="session")
def rebuilt_cleaner(tmp_path_factory):
    assert os.path.exists(GO_SOURCE), f"Go source missing at {GO_SOURCE}"
    source_stat = os.lstat(GO_SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"{GO_SOURCE} must be a regular file"

    output = str(tmp_path_factory.mktemp("build") / "cleaner")
    env = os.environ.copy()
    env["CGO_ENABLED"] = "0"
    subprocess.run(
        ["go", "build", "-trimpath", "-o", output, GO_SOURCE],
        env=env,
        capture_output=True,
        text=True,
        check=True,
        timeout=60,
    )
    return output


def test_go_cleaner_exists():
    """Test that the compiled Go cleaner exists and is executable."""
    assert os.path.exists(GO_CLEANER), f"Go cleaner missing at {GO_CLEANER}"
    cleaner_stat = os.lstat(GO_CLEANER)
    assert stat.S_ISREG(cleaner_stat.st_mode), f"{GO_CLEANER} must be a regular file, not a symlink or wrapper link"
    assert os.access(GO_CLEANER, os.X_OK), f"{GO_CLEANER} is not executable"

    assert not os.path.samefile(GO_CLEANER, LEGACY), "Go cleaner must not be the legacy executable"
    assert file_hash(GO_CLEANER) != file_hash(LEGACY), "Go cleaner is byte-identical to the legacy executable"

    go_info = subprocess.run(
        ["go", "version", "-m", GO_CLEANER],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert go_info.returncode == 0, f"{GO_CLEANER} is not a Go-built executable"


def test_fuzz_equivalence():
    """Fuzz test the submitted Go cleaner against the legacy cleaner."""
    for i, input_str in enumerate(generated_inputs()):
        legacy_output = run_program(LEGACY, input_str)
        go_output = run_program(GO_CLEANER, input_str)
        assert go_output == legacy_output, (
            f"Output mismatch on iteration {i}.\n"
            f"Input: {input_str[:100]}...\n"
            f"Legacy output: {legacy_output[:100]}...\n"
            f"Go output: {go_output[:100]}...\n"
        )


def test_source_and_binary_work_without_legacy(rebuilt_cleaner):
    """Require both the submitted binary and a fresh source build to work without filesystem access to the oracle."""
    for i, input_str in enumerate(generated_inputs()):
        expected = run_program(LEGACY, input_str)
        submitted_output = run_isolated(GO_CLEANER, input_str)
        rebuilt_output = run_isolated(rebuilt_cleaner, input_str)

        assert submitted_output == expected, (
            f"Submitted Go executable failed isolated test on iteration {i}"
        )
        assert rebuilt_output == expected, (
            f"Freshly compiled cleaner.go failed isolated test on iteration {i}"
        )


def test_setup_db_script():
    """Test that the setup_db script exists, runs, and creates the correct DB schema."""
    script_path = "/home/user/setup_db.sh"
    assert os.path.exists(script_path), f"Database setup script missing at {script_path}"

    subprocess.run(["bash", script_path], check=True)

    db_check = subprocess.run(
        ["psql", "-U", "postgres", "-tAc", "SELECT 1 FROM pg_database WHERE datname='sensor_data'"],
        capture_output=True, text=True
    )
    assert db_check.stdout.strip() == "1", "Database 'sensor_data' does not exist."

    table_check = subprocess.run(
        ["psql", "-U", "postgres", "-d", "sensor_data", "-tAc",
         "SELECT column_name, data_type FROM information_schema.columns WHERE table_name='cleaned_features' ORDER BY column_name"],
        capture_output=True, text=True
    )

    columns = table_check.stdout.strip().split("\n")
    assert len(columns) == 2, f"Expected 2 columns in cleaned_features, got {len(columns)}"

    col_dict = {}
    for col in columns:
        parts = col.split("|")
        if len(parts) == 2:
            col_dict[parts[0]] = parts[1]

    assert "id" in col_dict, "Column 'id' missing"
    assert "value" in col_dict, "Column 'value' missing"
    assert col_dict["id"] == "integer", f"Expected 'id' to be integer, got {col_dict['id']}"
    assert col_dict["value"] == "double precision", f"Expected 'value' to be double precision, got {col_dict['value']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
