#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import textwrap
import pytest

SOURCE = "/home/user/graph_engine.cpp"
ENGINE = "/home/user/engine"
VIEW = "/home/user/view.txt"
FRESH_ENGINE = "/tmp/engine_from_submitted_source"
HARNESS = "/tmp/graph_engine_harness"

EXPECTED_MAIN_OUTPUT = [
    "0,9,200",
    "3,4,120",
    "5,6,120",
]


def run_with_timeout(command, seconds=5):
    result = subprocess.run(
        ["timeout", f"{seconds}s"] + command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode != 124, f"Command timed out (possible deadlock): {command}"
    assert result.returncode == 0, (
        f"Command failed: {command}\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def read_view():
    assert os.path.isfile(VIEW), f"The output file {VIEW} does not exist."
    with open(VIEW, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_executable_exists():
    executable_path = ENGINE
    assert os.path.isfile(executable_path), f"The compiled executable {executable_path} does not exist. Did you compile the code?"
    assert os.access(executable_path, os.X_OK), f"The file {executable_path} is not executable."
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted engine is not a compiled ELF executable."

    if os.path.exists(VIEW):
        os.remove(VIEW)
    run_with_timeout([ENGINE], 5)


def test_view_txt_exists_and_correct():
    view_path = VIEW
    assert os.path.isfile(view_path), f"The output file {view_path} does not exist. Did the program run successfully without deadlocking?"

    lines = read_view()
    expected = EXPECTED_MAIN_OUTPUT

    assert lines == expected, (
        f"The contents of {view_path} are incorrect.\n"
        f"Expected:\n{expected}\n"
        f"Got:\n{lines}\n"
        "Ensure filtering (amount >= 50), sorting (amount desc, src asc, dst asc), and pagination (limit 3, offset 0) are correctly implemented."
    )


def test_submitted_source_compiles_and_runs():
    assert os.path.isfile(SOURCE), f"Missing required source file {SOURCE}"
    compile_result = subprocess.run(
        ["g++", "-std=c++11", "-pthread", SOURCE, "-o", FRESH_ENGINE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert compile_result.returncode == 0, (
        "The submitted graph_engine.cpp does not compile with the required command.\n"
        + compile_result.stdout + compile_result.stderr
    )

    if os.path.exists(VIEW):
        os.remove(VIEW)
    run_with_timeout([FRESH_ENGINE], 5)
    assert read_view() == EXPECTED_MAIN_OUTPUT


@pytest.fixture(scope="session")
def harness():
    harness_source = r'''
#define main submitted_graph_engine_main
#include "/home/user/graph_engine.cpp"
#undef main

#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

int main(int argc, char **argv) {
    if (argc >= 2 && std::string(argv[1]) == "deadlock") {
        transactions.clear();
        for (int i = 0; i < 10; ++i) node_balances[i] = 100000;

        const std::vector<std::pair<int, int> > pairs = {
            {1, 2}, {8, 3}, {0, 9}, {6, 4}, {2, 7}
        };
        for (int repeat = 0; repeat < 4; ++repeat) {
            for (const auto &p : pairs) {
                std::thread a(process_transaction, p.first, p.second, 1);
                std::thread b(process_transaction, p.second, p.first, 1);
                a.join();
                b.join();
            }
        }
        return 0;
    }

    if (argc != 6 || std::string(argv[1]) != "materialize") return 2;

    transactions.clear();
    std::ifstream input(argv[2]);
    int src, dst, amount;
    char comma1, comma2;
    while (input >> src >> comma1 >> dst >> comma2 >> amount) {
        if (comma1 != ',' || comma2 != ',') return 3;
        transactions.push_back({src, dst, amount});
    }

    int min_amount = std::atoi(argv[3]);
    int limit = std::atoi(argv[4]);
    int offset = std::atoi(argv[5]);
    materialize_top_transactions(min_amount, limit, offset);
    return 0;
}
'''
    path = "/tmp/graph_engine_harness.cpp"
    with open(path, "w") as f:
        f.write(textwrap.dedent(harness_source))

    result = subprocess.run(
        ["g++", "-std=c++11", "-pthread", path, "-o", HARNESS],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, (
        "Could not compile a test harness against graph_engine.cpp.\n"
        + result.stdout + result.stderr
    )
    return HARNESS


def test_opposite_transactions_do_not_deadlock(harness):
    run_with_timeout([harness, "deadlock"], 5)


def expected_projection(data, min_amount, limit, offset):
    filtered = [row for row in data if row[2] >= min_amount]
    filtered.sort(key=lambda row: (-row[2], row[0], row[1]))
    return filtered[offset:offset + limit]


def test_materialization_filter_sort_pagination_and_edges(harness):
    rng = random.Random(817263)
    data = [
        (9, 1, 120), (3, 8, 120), (3, 2, 120), (5, 6, 49),
        (0, 4, 200), (7, 1, 50), (2, 9, 50), (2, 3, 50),
    ]
    data.extend(
        (rng.randrange(10), rng.randrange(10), rng.randrange(0, 181))
        for _ in range(37)
    )

    dataset_path = "/tmp/materialization_input.csv"
    with open(dataset_path, "w") as f:
        for src, dst, amount in data:
            f.write(f"{src},{dst},{amount}\n")

    cases = [
        (50, 3, 0),
        (0, 20, 4),
        (100, 5, 1),
        (75, 0, 0),
        (121, 7, 2),
        (50, 4, len(data) + 10),
    ]

    for min_amount, limit, offset in cases:
        if os.path.exists(VIEW):
            os.remove(VIEW)
        run_with_timeout([
            harness, "materialize", dataset_path,
            str(min_amount), str(limit), str(offset)
        ], 5)

        expected_rows = expected_projection(data, min_amount, limit, offset)
        expected_lines = [f"{src},{dst},{amount}" for src, dst, amount in expected_rows]
        assert read_view() == expected_lines, (
            f"Incorrect projection for min_amount={min_amount}, "
            f"limit={limit}, offset={offset}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
