#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import shutil
import secrets
import subprocess
import tempfile
from decimal import Decimal

import pytest


def run_as_user(path, timeout=20):
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", path],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_execute_required_workflow():
    for path in (
        "/home/user/clibs/libmatrix.so",
        "/home/user/output_v1.log",
        "/home/user/final_v2.csv",
    ):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_as_user("/home/user/run_app.sh")
    run_as_user("/home/user/migrate.sh")


def test_run_app_sh_executable():
    path = "/home/user/run_app.sh"
    assert os.path.isfile(path), f"Script {path} does not exist. Did you create it?"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {path} is not executable."


def test_migrate_sh_executable():
    path = "/home/user/migrate.sh"
    assert os.path.isfile(path), f"Script {path} does not exist. Did you create it?"
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {path} is not executable."


def test_symlink_correct():
    symlink_path = "/home/user/clibs/libmatrix.so"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symlink."

    target = os.readlink(symlink_path)
    expected_targets = ["libmatrix.so.1.8.5", "/home/user/clibs/libmatrix.so.1.8.5"]
    assert target in expected_targets, f"Symlink points to incorrect version: {target}. Expected libmatrix.so.1.8.5"


def test_output_log_exists():
    log_path = "/home/user/output_v1.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did math_runner execute successfully?"


def test_final_csv_correct():
    csv_path = "/home/user/final_v2.csv"
    assert os.path.isfile(csv_path), f"CSV file {csv_path} does not exist. Did migrate.sh run successfully?"

    with open(csv_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 6, f"Expected 6 lines in {csv_path} (1 header + 5 data rows), but found {len(content)}."
    assert content[0] == "MatrixID,Determinant,WorkerID", f"Incorrect header in {csv_path}. Found: {content[0]}"

    expected_data = [
        "1003,105.7,3",
        "1002,42.00,2",
        "1004,14.22,4",
        "1005,8.11,4",
        "1001,-99.50,1",
    ]

    for i, expected_line in enumerate(expected_data):
        assert content[i + 1] == expected_line, f"Line {i+2} in {csv_path} is incorrect. Expected '{expected_line}', found '{content[i+1]}'."


def test_run_app_selects_highest_compatible_version_and_executes_runner():
    clibs = "/home/user/clibs"
    runner = "/home/user/math_runner"
    marker = "/home/user/.verifier_runner_marker"
    backup_root = tempfile.mkdtemp(prefix="run-app-backup-")
    backup_clibs = os.path.join(backup_root, "clibs")
    backup_runner = os.path.join(backup_root, "math_runner")

    shutil.copy2(runner, backup_runner)
    os.rename(clibs, backup_clibs)

    token = secrets.token_hex(16)
    versions = {(1, 5, 0), (1, 6, 1)}
    while len(versions) < 7:
        versions.add((1, 5 + secrets.randbelow(16), secrets.randbelow(30)))
    versions.update({(1, 4, 99), (2, 0, 0), (2, 3, 7)})
    compatible = [v for v in versions if (1, 5, 0) <= v < (2, 0, 0)]
    expected_version = max(compatible)
    expected_name = "libmatrix.so.%d.%d.%d" % expected_version

    try:
        os.mkdir(clibs, 0o777)
        os.chmod(clibs, 0o777)
        for version in versions:
            path = os.path.join(clibs, "libmatrix.so.%d.%d.%d" % version)
            with open(path, "w"):
                pass
            os.chmod(path, 0o666)

        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

        with open(runner, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("case \"${LD_LIBRARY_PATH:-}\" in\n")
            f.write("  /home/user/clibs|/home/user/clibs:*|*:/home/user/clibs|*:/home/user/clibs:*) ;;\n")
            f.write("  *) exit 41 ;;\n")
            f.write("esac\n")
            f.write(f"printf '%s' '{token}' > '{marker}'\n")
        os.chmod(runner, 0o755)

        run_as_user("/home/user/run_app.sh")

        link = os.path.join(clibs, "libmatrix.so")
        assert os.path.islink(link), "run_app.sh did not create libmatrix.so as a symlink"
        target = os.readlink(link)
        assert os.path.basename(target) == expected_name, (
            f"Expected highest compatible version {expected_name}, but symlink target was {target}"
        )
        assert os.path.exists(marker), "run_app.sh did not execute /home/user/math_runner"
        with open(marker) as f:
            assert f.read() == token, "Unexpected runner marker contents"
    finally:
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass
        if os.path.exists(clibs) or os.path.islink(clibs):
            shutil.rmtree(clibs, ignore_errors=True)
        os.rename(backup_clibs, clibs)
        shutil.copy2(backup_runner, runner)
        shutil.rmtree(backup_root, ignore_errors=True)


def test_migrate_parses_and_numerically_sorts_fresh_input():
    log_path = "/home/user/output_v1.log"
    csv_path = "/home/user/final_v2.csv"
    backup_root = tempfile.mkdtemp(prefix="migrate-backup-")
    log_backup = os.path.join(backup_root, "output_v1.log")
    csv_backup = os.path.join(backup_root, "final_v2.csv")

    if os.path.exists(log_path):
        shutil.copy2(log_path, log_backup)
    if os.path.exists(csv_path):
        shutil.copy2(csv_path, csv_backup)

    negative_values = secrets.SystemRandom().sample(range(-90000, -100), 4)
    positive_values = secrets.SystemRandom().sample(range(100, 90000), 5)
    numeric_values = negative_values + positive_values
    secrets.SystemRandom().shuffle(numeric_values)

    rows = []
    base_id = 20000 + secrets.randbelow(50000)
    for index, number in enumerate(numeric_values):
        determinant = f"{number / 100:.2f}"
        matrix_id = str(base_id + index)
        worker = str(1 + secrets.randbelow(12))
        rows.append((matrix_id, determinant, worker))

    shuffled = rows[:]
    secrets.SystemRandom().shuffle(shuffled)

    try:
        with open(log_path, "w") as f:
            for matrix_id, determinant, worker in shuffled:
                f.write(
                    f"[Worker {worker}] Schema=v1 | Determinant={determinant} | MatrixID={matrix_id}\n"
                )
        os.chmod(log_path, 0o666)
        try:
            os.remove(csv_path)
        except FileNotFoundError:
            pass

        run_as_user("/home/user/migrate.sh")

        with open(csv_path) as f:
            actual = f.read().strip().splitlines()

        expected_rows = sorted(rows, key=lambda row: Decimal(row[1]), reverse=True)
        expected = ["MatrixID,Determinant,WorkerID"] + [
            f"{matrix_id},{determinant},{worker}"
            for matrix_id, determinant, worker in expected_rows
        ]
        assert actual == expected, f"Migrated CSV was incorrect.\nExpected: {expected}\nActual: {actual}"
    finally:
        if os.path.exists(log_backup):
            shutil.copy2(log_backup, log_path)
        if os.path.exists(csv_backup):
            shutil.copy2(csv_backup, csv_path)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
