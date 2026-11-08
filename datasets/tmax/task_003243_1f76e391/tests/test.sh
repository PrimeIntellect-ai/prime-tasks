#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import secrets
import subprocess
import pytest

CPP_FILE = "/home/user/cost_analyzer.cpp"
BASH_SCRIPT = "/home/user/run_analysis.sh"
EXECUTABLE = "/home/user/cost_analyzer"
CSV_FILE = "/home/user/cost_report.csv"
STORAGE_DIR = "/home/user/cloud_storage"


def unlink_if_present(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def run_command(command, timeout=30):
    return subprocess.run(
        command,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Compiled executable {path} is missing."
    assert os.access(path, os.X_OK), f"Compiled executable {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def get_expected_costs(base_dir):
    expected_data = {}
    if not os.path.isdir(base_dir):
        return expected_data

    for user in os.listdir(base_dir):
        user_dir = os.path.join(base_dir, user)
        if not os.path.isdir(user_dir):
            continue

        total_bytes = 0
        total_cost = 0

        for root, _, files in os.walk(user_dir):
            for file in files:
                filepath = os.path.join(root, file)
                size = os.path.getsize(filepath)
                total_bytes += size

                ext = os.path.splitext(file)[1].lower()
                if ext == '.log':
                    total_cost += size * 1
                elif ext == '.db':
                    total_cost += size * 5
                elif ext == '.tmp':
                    total_cost += size * 0
                else:
                    total_cost += size * 2

        expected_data[user] = {"TotalBytes": total_bytes, "TotalCost": total_cost}

    return expected_data


@pytest.fixture(scope="session", autouse=True)
def exercise_build_and_program():
    assert os.path.isfile(CPP_FILE), f"C++ source file {CPP_FILE} is missing."
    assert os.path.isfile(BASH_SCRIPT), f"Bash script {BASH_SCRIPT} is missing."
    assert os.access(BASH_SCRIPT, os.X_OK), f"Bash script {BASH_SCRIPT} is not executable."
    assert os.path.isdir(STORAGE_DIR), f"Storage directory {STORAGE_DIR} is missing."

    # Add data unknown when the submission was produced, including nested files and
    # every cost category, so a report for only the original fixed fixture fails.
    token = secrets.token_hex(6)
    random_user = f"verify_{token}"
    nested = os.path.join(STORAGE_DIR, random_user, "nested", "deeper")
    os.makedirs(nested, exist_ok=False)
    sizes = [secrets.randbelow(3000) + 137 for _ in range(5)]
    generated_files = [
        (os.path.join(STORAGE_DIR, random_user, "events.log"), sizes[0]),
        (os.path.join(STORAGE_DIR, random_user, "nested", "records.db"), sizes[1]),
        (os.path.join(nested, "scratch.tmp"), sizes[2]),
        (os.path.join(nested, "archive.bin"), sizes[3]),
        (os.path.join(STORAGE_DIR, "alice", f"extra_{token}"), sizes[4]),
    ]
    for path, size in generated_files:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(os.urandom(size))

    with open(CPP_FILE, "rb") as f:
        original_source = f.read()

    marker = f"/tmp/cost_analyzer_probe_{secrets.token_hex(8)}"
    probe_source = f'''#include <fstream>\nint main() {{ std::ofstream out("{marker}"); out << "executed"; return out ? 0 : 2; }}\n'''

    try:
        # Verify that the wrapper really compiles the requested source to the
        # requested executable and then executes that executable.
        with open(CPP_FILE, "w") as f:
            f.write(probe_source)
        unlink_if_present(marker)
        unlink_if_present(EXECUTABLE)
        unlink_if_present(CSV_FILE)
        probe = run_command([BASH_SCRIPT])
        assert probe.returncode == 0, (
            f"Wrapper failed while compiling/executing a valid probe source. "
            f"stdout={probe.stdout!r}, stderr={probe.stderr!r}"
        )
        assert_elf_executable(EXECUTABLE)
        assert os.path.isfile(marker), "The wrapper did not execute the compiled program."

        # Verify the required robust compilation-failure behavior.
        with open(CPP_FILE, "w") as f:
            f.write("#error verifier induced compilation failure\n")
        unlink_if_present(EXECUTABLE)
        failed_build = run_command([BASH_SCRIPT])
        assert failed_build.returncode == 1, (
            "The wrapper must exit with code 1 when compilation fails; "
            f"got {failed_build.returncode}. stdout={failed_build.stdout!r}, "
            f"stderr={failed_build.stderr!r}"
        )
    finally:
        with open(CPP_FILE, "wb") as f:
            f.write(original_source)
        unlink_if_present(marker)

    # Run the submitted wrapper on the actual randomized storage fixture.
    unlink_if_present(EXECUTABLE)
    unlink_if_present(CSV_FILE)
    result = run_command([BASH_SCRIPT])
    assert result.returncode == 0, (
        f"run_analysis.sh failed. stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert_elf_executable(EXECUTABLE)
    assert os.path.isfile(CSV_FILE), "The wrapper did not produce cost_report.csv."

    # Execute the compiled artifact itself after removing the wrapper's report,
    # proving that the C++ program, rather than shell-side report generation,
    # creates the report.
    unlink_if_present(CSV_FILE)
    direct = run_command([EXECUTABLE])
    assert direct.returncode == 0, (
        f"Compiled cost_analyzer failed. stdout={direct.stdout!r}, stderr={direct.stderr!r}"
    )
    assert os.path.isfile(CSV_FILE), "The compiled C++ program did not generate cost_report.csv."


def test_cpp_file_exists():
    cpp_file = "/home/user/cost_analyzer.cpp"
    assert os.path.isfile(cpp_file), f"C++ source file {cpp_file} is missing."


def test_bash_script_exists_and_executable():
    bash_script = "/home/user/run_analysis.sh"
    assert os.path.isfile(bash_script), f"Bash script {bash_script} is missing."
    assert os.access(bash_script, os.X_OK), f"Bash script {bash_script} is not executable."


def test_cost_report_csv():
    csv_file = "/home/user/cost_report.csv"
    assert os.path.isfile(csv_file), f"Output file {csv_file} is missing."

    expected_data = get_expected_costs("/home/user/cloud_storage")
    assert expected_data, "Could not compute expected data; /home/user/cloud_storage might be missing."

    with open(csv_file, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{csv_file} is empty."

    header = rows[0]
    expected_header = ["Username", "TotalBytes", "TotalCost"]
    assert header == expected_header, f"Header in {csv_file} is {header}, expected {expected_header}."

    parsed_data = {}
    for row in rows[1:]:
        assert len(row) == 3, f"Row {row} does not have exactly 3 columns."
        username, total_bytes, total_cost = row
        parsed_data[username] = {
            "TotalBytes": int(total_bytes),
            "TotalCost": int(total_cost)
        }

    expected_users = sorted(expected_data.keys())
    actual_users = list(parsed_data.keys())

    assert actual_users == expected_users, f"Users in CSV are not sorted alphabetically or do not match expected. Actual: {actual_users}, Expected: {expected_users}"

    for user in expected_users:
        expected_bytes = expected_data[user]["TotalBytes"]
        expected_cost = expected_data[user]["TotalCost"]
        actual_bytes = parsed_data[user]["TotalBytes"]
        actual_cost = parsed_data[user]["TotalCost"]

        assert actual_bytes == expected_bytes, f"User {user} has TotalBytes {actual_bytes}, expected {expected_bytes}."
        assert actual_cost == expected_cost, f"User {user} has TotalCost {actual_cost}, expected {expected_cost}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
