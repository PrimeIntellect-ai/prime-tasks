#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import stat
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "detect_deadlock.c")
REPORT = os.path.join(HOME, "deadlock_report.txt")
TRANSACTIONS = os.path.join(HOME, "transactions.csv")
COSTS = os.path.join(HOME, "costs.csv")
EXECUTABLE = "/tmp/detect_deadlock_test"

ORIGINAL_TRANSACTIONS = """tx_id,waits_for_tx_id
10,20
20,30
30,40
40,50
50,60
60,70
70,30
80,10
90,80
100,110
110,120
"""

ORIGINAL_COSTS = """tx_id,cost
10,100
20,150
30,200
40,250
50,300
60,350
70,400
80,50
90,75
100,500
110,600
120,700
"""


def write_inputs(transactions, costs):
    with open(TRANSACTIONS, "w") as f:
        f.write(transactions)
    with open(COSTS, "w") as f:
        f.write(costs)


def run_program():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    result = subprocess.run(
        [EXECUTABLE], cwd=HOME, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"The compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def assert_report(expected):
    report_path = "/home/user/deadlock_report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} was not created."

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert content == expected, (
        f"The content of {report_path} is incorrect.\n"
        f"Expected:\n{expected}\n\n"
        f"Got:\n{content}"
    )


def derive_expected(transactions_text, costs_text):
    graph = {}
    nodes = set()
    for line in transactions_text.strip().splitlines()[1:]:
        left, right = map(int, line.split(","))
        graph.setdefault(left, []).append(right)
        nodes.update((left, right))

    costs = {}
    for line in costs_text.strip().splitlines()[1:]:
        tx_id, cost = map(int, line.split(","))
        costs[tx_id] = cost

    state = {}
    stack = []
    positions = {}
    cycles = []

    def visit(node):
        state[node] = 1
        positions[node] = len(stack)
        stack.append(node)
        for nxt in graph.get(node, []):
            if state.get(nxt, 0) == 0:
                visit(nxt)
            elif state.get(nxt) == 1:
                cycles.append(stack[positions[nxt]:].copy())
        stack.pop()
        positions.pop(node)
        state[node] = 2

    for node in nodes:
        if state.get(node, 0) == 0:
            visit(node)

    assert len(cycles) == 1
    cycle = sorted(cycles[0])
    total = sum(costs[node] for node in cycle)
    return f"Deadlock IDs: {','.join(map(str, cycle))}\nTotal Cost: {total}"


def make_random_case(rng):
    ids = rng.sample(range(1, 901), 15)
    cycle_size = rng.randint(3, 7)
    cycle = ids[:cycle_size]
    other = ids[cycle_size:]

    edges = []
    for i, node in enumerate(cycle):
        edges.append((node, cycle[(i + 1) % len(cycle)]))

    if other:
        edges.append((other[0], cycle[0]))
        for i in range(1, len(other)):
            edges.append((other[i], other[i - 1]))

    rng.shuffle(edges)
    transactions = "tx_id,waits_for_tx_id\n" + "".join(
        f"{left},{right}\n" for left, right in edges
    )

    cost_rows = [(node, rng.randint(1, 2000)) for node in ids]
    rng.shuffle(cost_rows)
    costs = "tx_id,cost\n" + "".join(
        f"{node},{cost}\n" for node, cost in cost_rows
    )
    return transactions, costs


def test_deadlock_program_and_report():
    assert os.path.isfile(SOURCE), f"The C source file {SOURCE} was not created."
    mode = os.stat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"The C source path {SOURCE} is not a regular file."

    compile_result = subprocess.run(
        ["gcc", SOURCE, "-O2", "-o", EXECUTABLE],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"The C program did not compile.\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )

    write_inputs(ORIGINAL_TRANSACTIONS, ORIGINAL_COSTS)
    run_program()
    expected = "Deadlock IDs: 30,40,50,60,70\nTotal Cost: 1500"
    assert_report(expected)

    rng = random.SystemRandom()
    for _ in range(2):
        transactions, costs = make_random_case(rng)
        expected = derive_expected(transactions, costs)
        write_inputs(transactions, costs)
        run_program()
        assert_report(expected)

    # Restore the supplied inputs and ensure the requested final report remains.
    write_inputs(ORIGINAL_TRANSACTIONS, ORIGINAL_COSTS)
    run_program()
    assert_report("Deadlock IDs: 30,40,50,60,70\nTotal Cost: 1500")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
