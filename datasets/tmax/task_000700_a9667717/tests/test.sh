#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

PROJECT = "/home/user/project"
EXECUTABLE = os.path.join(PROJECT, "analyzer")
DATABASE = os.path.join(PROJECT, "sensor_data.db")


@pytest.fixture(scope="session", autouse=True)
def rebuild_project():
    clean = subprocess.run(
        ["make", "clean"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert clean.returncode == 0, f"'make clean' failed:\n{clean.stdout}{clean.stderr}"
    assert not os.path.exists(EXECUTABLE), "The Makefile's clean target did not remove analyzer."

    build = subprocess.run(
        ["make"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert build.returncode == 0, f"The project failed to build with make:\n{build.stdout}{build.stderr}"


def expected_output(values):
    mean = math.fsum(values) / len(values)
    variance = math.fsum((x - mean) ** 2 for x in values) / len(values)
    return f"Result: {math.sqrt(variance):.4f}"


def run_analyzer(timeout=5):
    return subprocess.run(
        [EXECUTABLE], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout
    )


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), "The executable 'analyzer' was not found."
    assert os.access(EXECUTABLE, os.X_OK), "The file 'analyzer' is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The Makefile did not produce a native executable."


def test_config_ini_exists():
    config_path = os.path.join(PROJECT, "config.ini")
    assert os.path.isfile(config_path), "The file 'config.ini' was not created to prevent the deadlock."


def test_database_recovered():
    assert os.path.isfile(DATABASE), "The database file 'sensor_data.db' is missing."

    try:
        conn = sqlite3.connect(DATABASE)
        cursor = conn.cursor()
        cursor.execute("SELECT value FROM measurements ORDER BY value ASC;")
        rows = cursor.fetchall()
        conn.close()
    except sqlite3.DatabaseError:
        pytest.fail("The database 'sensor_data.db' is still corrupted or invalid.")
    except sqlite3.OperationalError:
        pytest.fail("The 'measurements' table was not found in the recovered database.")

    values = [row[0] for row in rows]
    expected_values = [10.0, 12.0, 15.0, 18.0, 20.0]
    assert values == expected_values, f"Database values do not match the expected recovered data. Got: {values}"


def test_stats_function_computes_population_stddev():
    harness_source = r'''
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <vector>
#include "stats.h"

int main(int argc, char** argv) {
    std::vector<double> values;
    for (int i = 1; i < argc; ++i) values.push_back(std::strtod(argv[i], nullptr));
    std::cout << std::setprecision(17) << calculate_pop_stddev(values) << "\n";
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "stats_harness.cpp")
        binary = os.path.join(td, "stats_harness")
        with open(source, "w") as f:
            f.write(harness_source)
        compile_result = subprocess.run(
            ["g++", "-std=c++11", "-I", PROJECT, source,
             os.path.join(PROJECT, "stats.cpp"), "-o", binary],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert compile_result.returncode == 0, (
            f"stats.cpp could not be compiled independently:\n{compile_result.stderr}"
        )

        for values in ([2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0],
                       [-3.5, 0.25, 6.75, 10.0]):
            result = subprocess.run(
                [binary] + [str(x) for x in values], text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
            )
            assert result.returncode == 0, f"stats harness failed: {result.stderr}"
            actual = float(result.stdout.strip())
            mean = math.fsum(values) / len(values)
            expected = math.sqrt(math.fsum((x - mean) ** 2 for x in values) / len(values))
            assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
                f"calculate_pop_stddev returned {actual}, expected {expected} for {values}"
            )


def test_analyzer_runs_and_uses_database():
    original_values = [10.0, 12.0, 15.0, 18.0, 20.0]
    normal = run_analyzer()
    assert normal.returncode == 0, f"analyzer failed:\n{normal.stderr}"
    assert normal.stdout.strip() == expected_output(original_values), (
        f"analyzer output was incorrect: {normal.stdout!r}"
    )

    backup = DATABASE + ".verifier-backup"
    replacement = DATABASE + ".verifier-input"
    shutil.copyfile(DATABASE, backup)
    alternate_values = [1.25, 2.5, 8.0, 11.75]
    try:
        if os.path.exists(replacement):
            os.unlink(replacement)
        conn = sqlite3.connect(replacement)
        conn.execute("CREATE TABLE measurements (value REAL)")
        conn.executemany("INSERT INTO measurements(value) VALUES (?)",
                         [(x,) for x in alternate_values])
        conn.commit()
        conn.close()
        os.replace(replacement, DATABASE)

        alternate = run_analyzer()
        assert alternate.returncode == 0, f"analyzer failed on a valid database:\n{alternate.stderr}"
        assert alternate.stdout.strip() == expected_output(alternate_values), (
            "analyzer did not compute its result from the database; "
            f"got {alternate.stdout!r}"
        )
    finally:
        if os.path.exists(replacement):
            os.unlink(replacement)
        os.replace(backup, DATABASE)


def test_solution_txt_correct():
    solution_path = "/home/user/solution.txt"
    assert os.path.isfile(solution_path), "The file 'solution.txt' was not found."

    with open(solution_path, "r") as f:
        content = f.read().strip()

    expected_content = "Result: 3.6878"
    assert content == expected_content, f"The content of 'solution.txt' is incorrect. Expected '{expected_content}', but got '{content}'."

    result = run_analyzer()
    assert result.returncode == 0, f"The rebuilt analyzer failed:\n{result.stderr}"
    assert content == result.stdout.strip(), "solution.txt is not the standard output of the rebuilt analyzer."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
