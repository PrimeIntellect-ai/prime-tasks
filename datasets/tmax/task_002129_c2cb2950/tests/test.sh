#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import shutil
import subprocess

PROJECT = "/home/user/backup_analyzer"
JSONL_PATH = "/home/user/backups.jsonl"
CSV_PATH = "/home/user/critical_backups.csv"
TARGET_DIR = "/tmp/verifier_backup_analyzer_target"


def expected_csv(backups):
    children_count = {b["id"]: 0 for b in backups}
    for backup in backups:
        parent_id = backup.get("parent_id")
        if parent_id is not None and parent_id in children_count:
            children_count[parent_id] += 1

    regions = {}
    for backup in backups:
        regions.setdefault(backup["region"], []).append(backup)

    region_ranks = {}
    for region_backups in regions.values():
        ordered = sorted(region_backups, key=lambda b: (-b["size_bytes"], b["id"]))
        for rank, backup in enumerate(ordered, start=1):
            region_ranks[backup["id"]] = rank

    rows = sorted(backups, key=lambda b: b["id"])
    result = [["id", "children_count", "region_rank"]]
    result.extend([
        [b["id"], str(children_count[b["id"]]), str(region_ranks[b["id"]])]
        for b in rows
    ])
    return result


def read_backups():
    backups = []
    with open(JSONL_PATH, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                backups.append(json.loads(line))
    return backups


def read_actual_csv():
    actual = []
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle):
            if any(cell.strip() for cell in row):
                actual.append([cell.strip() for cell in row])
    return actual


def assert_csv_matches(backups):
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} was not created."
    actual = read_actual_csv()
    expected = expected_csv(backups)

    assert len(actual) > 0, f"CSV file {CSV_PATH} is empty."
    assert actual[0] == ["id", "children_count", "region_rank"], "CSV header is incorrect."
    assert len(actual) == len(expected), f"Expected {len(expected)} rows, got {len(actual)}."
    for i, (actual_row, expected_row) in enumerate(zip(actual, expected)):
        assert actual_row == expected_row, \
            f"Row {i + 1} mismatch: expected {expected_row}, got {actual_row}."


def write_fixture(backups):
    with open(JSONL_PATH, "w", encoding="utf-8") as handle:
        for backup in backups:
            handle.write(json.dumps(backup, separators=(",", ":")) + "\n")


def run_program(executable):
    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    subprocess.run([executable], cwd=PROJECT, check=True, timeout=30)
    assert os.path.isfile(CSV_PATH), f"Output file {CSV_PATH} was not created."


def random_fixture():
    rng = random.SystemRandom()
    token = secrets.token_hex(5)
    regions = [f"region-{token}-{i}" for i in range(4)]
    sizes = [17, 17, 64, 64, 64, 301, 900, 2048]
    backups = []
    for i in range(28):
        backup_id = f"node-{token}-{i:02d}-{secrets.token_hex(2)}"
        if i == 0 or rng.randrange(4) == 0:
            parent_id = None
        else:
            parent_id = rng.choice(backups)["id"]
        backups.append({
            "id": backup_id,
            "parent_id": parent_id,
            "size_bytes": rng.choice(sizes),
            "region": rng.choice(regions),
        })
    rng.shuffle(backups)
    return backups


def test_critical_backups_csv():
    assert os.path.isfile(JSONL_PATH), f"{JSONL_PATH} is missing."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."
    main_rs = os.path.join(PROJECT, "src", "main.rs")
    assert os.path.isfile(main_rs), "src/main.rs is missing."
    assert os.path.getsize(main_rs) > 0, "src/main.rs is empty."

    with open(JSONL_PATH, "rb") as handle:
        original_jsonl = handle.read()
    original_csv = None
    if os.path.isfile(CSV_PATH):
        with open(CSV_PATH, "rb") as handle:
            original_csv = handle.read()
    final_original_output = None

    try:
        shutil.rmtree(TARGET_DIR, ignore_errors=True)
        env = os.environ.copy()
        env["CARGO_TARGET_DIR"] = TARGET_DIR

        subprocess.run(
            ["cargo", "build", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
            cwd=PROJECT, env=env, check=True, timeout=180,
        )
        metadata_result = subprocess.run(
            ["cargo", "metadata", "--no-deps", "--format-version", "1",
             "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
            cwd=PROJECT, env=env, check=True, timeout=30,
            stdout=subprocess.PIPE, text=True,
        )
        metadata = json.loads(metadata_result.stdout)
        root_id = metadata.get("resolve", {}).get("root")
        root_package = next((p for p in metadata["packages"] if p["id"] == root_id), None)
        assert root_package is not None, "Could not identify the Rust package."
        bin_targets = [t for t in root_package["targets"] if "bin" in t.get("kind", [])]
        assert len(bin_targets) == 1, "The project must provide one runnable binary target."

        executable = os.path.join(TARGET_DIR, "debug", bin_targets[0]["name"])
        assert os.path.isfile(executable), "Cargo did not produce the expected binary artifact."
        assert os.access(executable, os.X_OK), "Built Rust artifact is not executable."
        with open(executable, "rb") as handle:
            assert handle.read(4) == b"\x7fELF", "Built artifact is not a native executable."

        # Exercise the submitted program on the original input, replacing any
        # pre-created CSV so that the executable itself must produce the result.
        original_backups = read_backups()
        run_program(executable)
        assert_csv_matches(original_backups)
        with open(CSV_PATH, "rb") as handle:
            final_original_output = handle.read()

        # Exercise the same binary on fresh, unpredictable inputs to rule out a
        # solution that merely hardcodes the visible fixture.
        for _ in range(3):
            backups = random_fixture()
            write_fixture(backups)
            run_program(executable)
            assert_csv_matches(backups)
    finally:
        with open(JSONL_PATH, "wb") as handle:
            handle.write(original_jsonl)
        restored_csv = final_original_output if final_original_output is not None else original_csv
        if restored_csv is None:
            if os.path.exists(CSV_PATH):
                os.unlink(CSV_PATH)
        else:
            with open(CSV_PATH, "wb") as handle:
                handle.write(restored_csv)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
