#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import heapq
import secrets
import subprocess
from pathlib import Path

HOME = Path("/home/user")
DATA = HOME / "data"


def test_source_and_executable_exist():
    cpp_file = Path("/home/user/etl_processor.cpp")
    executable = Path("/home/user/etl_processor")

    assert cpp_file.exists(), "C++ source code /home/user/etl_processor.cpp does not exist."
    assert executable.exists(), "Compiled executable /home/user/etl_processor does not exist."
    assert os.access(executable, os.X_OK), "The file /home/user/etl_processor is not executable."
    assert cpp_file.is_file(), "/home/user/etl_processor.cpp is not a regular file."
    assert executable.is_file(), "/home/user/etl_processor is not a regular file."
    with executable.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/etl_processor is not a compiled ELF executable."


def test_summary_report_exists_and_correct():
    report_file = Path("/home/user/summary_report.csv")
    assert report_file.exists(), f"Output report {report_file} does not exist."

    expected_rows = [
        ["user_id", "name", "region", "total_completed_amount", "distance_to_whale"],
        ["1", "Alice", "US", "1200.0", "0"],
        ["2", "Bob", "UK", "500.0", "10"],
        ["3", "Charlie", "US", "100.0", "10"],
        ["4", "Diana", "CA", "0.0", "8"],
        ["5", "Eve", "UK", "2000.0", "0"],
        ["6", "Frank", "AU", "0.0", "-1"]
    ]

    with open(report_file, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, "The summary report is empty."
    assert actual_rows[0] == expected_rows[0], f"Header row is incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}."
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), got {len(actual_rows)}."

    for i in range(1, len(expected_rows)):
        expected = expected_rows[i]
        actual = actual_rows[i]

        assert actual[0] == expected[0], f"Row {i}: user_id mismatch. Expected {expected[0]}, got {actual[0]}."
        assert actual[1] == expected[1], f"Row {i}: name mismatch. Expected {expected[1]}, got {actual[1]}."
        assert actual[2] == expected[2], f"Row {i}: region mismatch. Expected {expected[2]}, got {actual[2]}."

        try:
            actual_amount = float(actual[3])
            expected_amount = float(expected[3])
            assert actual_amount == expected_amount, f"Row {i}: total_completed_amount mismatch. Expected {expected_amount}, got {actual_amount}."
            assert actual[3].endswith(".0") or "." in actual[3], f"Row {i}: total_completed_amount format issue. Expected 1 decimal place, got {actual[3]}."
        except ValueError:
            assert False, f"Row {i}: total_completed_amount '{actual[3]}' is not a valid float."

        assert actual[4] == expected[4], f"Row {i}: distance_to_whale mismatch. Expected {expected[4]}, got {actual[4]}."


def test_zz_executable_processes_altered_inputs():
    paths = [DATA / "users.csv", DATA / "transactions.jsonl", DATA / "network.edges", HOME / "summary_report.csv"]
    backups = {p: p.read_bytes() if p.exists() else None for p in paths}

    try:
        rng = secrets.SystemRandom()
        ids = sorted(rng.sample(range(100, 9000), 7))
        users = [
            (ids[0], "Nora", "WEST"),
            (ids[1], "Omar", "NORTH"),
            (ids[2], "Priya", "EAST"),
            (ids[3], "Quinn", "SOUTH"),
            (ids[4], "Ravi", "CENTRAL"),
            (ids[5], "Sara", "ISLAND"),
            (ids[6], "Tomas", "ISLAND"),
        ]

        with (DATA / "users.csv").open("w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["id", "name", "region"])
            writer.writerows(users)

        transactions = [
            {"tx_id": "a", "user_id": ids[0], "amount": 400.0, "status": "COMPLETED"},
            {"tx_id": "b", "user_id": ids[0], "amount": 600.0, "status": "COMPLETED"},
            {"tx_id": "c", "user_id": ids[1], "amount": 120.5, "status": "COMPLETED"},
            {"tx_id": "d", "user_id": ids[1], "amount": 50000.0, "status": "FAILED"},
            {"tx_id": "e", "user_id": ids[2], "amount": 99999.0, "status": "completed"},
            {"tx_id": "f", "user_id": ids[3], "amount": 1300.2, "status": "COMPLETED"},
            {"tx_id": "g", "user_id": ids[4], "amount": 999.9, "status": "COMPLETED"},
            {"tx_id": "h", "user_id": ids[6], "amount": 50.0, "status": "PENDING"},
        ]
        rng.shuffle(transactions)
        with (DATA / "transactions.jsonl").open("w", encoding="utf-8") as f:
            for tx in transactions:
                f.write(json.dumps(tx, separators=(",", ":")) + "\n")

        heavy = rng.randint(20, 35)
        edges = [
            (ids[1], ids[0], heavy),
            (ids[2], ids[1], 2),
            (ids[3], ids[2], 3),
            (ids[1], ids[3], 50),
            (ids[4], ids[2], 4),
            (ids[0], ids[4], 40),
            (ids[6], ids[5], 1),
        ]
        with (DATA / "network.edges").open("w", encoding="utf-8") as f:
            for a, b, weight in edges:
                f.write(f"{a} {b} {weight}\n")

        totals = {uid: 0.0 for uid, _, _ in users}
        for tx in transactions:
            if tx["status"] == "COMPLETED" and tx["user_id"] in totals:
                totals[tx["user_id"]] += float(tx["amount"])

        graph = {uid: [] for uid, _, _ in users}
        for a, b, weight in edges:
            graph.setdefault(a, []).append((b, weight))
            graph.setdefault(b, []).append((a, weight))

        whales = [uid for uid in totals if totals[uid] >= 1000.0]
        distances = {uid: float("inf") for uid, _, _ in users}
        queue = []
        for uid in whales:
            distances[uid] = 0
            heapq.heappush(queue, (0, uid))
        while queue:
            distance, node = heapq.heappop(queue)
            if distance != distances[node]:
                continue
            for neighbor, weight in graph.get(node, []):
                candidate = distance + weight
                if candidate < distances.get(neighbor, float("inf")):
                    distances[neighbor] = candidate
                    heapq.heappush(queue, (candidate, neighbor))

        expected_rows = [["user_id", "name", "region", "total_completed_amount", "distance_to_whale"]]
        for uid, name, region in sorted(users):
            distance = -1 if distances[uid] == float("inf") else distances[uid]
            expected_rows.append([str(uid), name, region, f"{totals[uid]:.1f}", str(distance)])

        report = HOME / "summary_report.csv"
        if report.exists():
            report.unlink()

        result = subprocess.run(
            [str(HOME / "etl_processor")],
            cwd=str(HOME),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f"etl_processor failed on altered inputs (exit {result.returncode}): {result.stderr}"
        assert report.exists(), "etl_processor did not create summary_report.csv when executed on altered inputs."

        with report.open("r", encoding="utf-8", newline="") as f:
            actual_rows = list(csv.reader(f))

        assert actual_rows == expected_rows, f"Report from altered inputs is incorrect.\nExpected: {expected_rows}\nActual: {actual_rows}"
        for row in actual_rows[1:]:
            assert len(row) == 5, f"Output row has the wrong number of columns: {row}"
            amount = row[3]
            assert amount.count(".") == 1 and len(amount.rsplit(".", 1)[1]) == 1, f"Amount is not formatted to exactly one decimal place: {amount}"
    finally:
        for path, content in backups.items():
            if content is None:
                if path.exists():
                    path.unlink()
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
