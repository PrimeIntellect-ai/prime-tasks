#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

MIGRATOR_DIR = Path("/home/user/migrator")

EXPECTED_MIGRATE_TEST = '''package main

import (
\t"reflect"
\t"sort"
\t"testing"
\t"testing/quick"
)

func TestMigrateProperties(t *testing.T) {
\tf := func(records []Legacy) bool {
\t\tmoderns := Migrate(records)

\t\tfor _, m := range moderns {
\t\t\tif !sort.IntsAreSorted(m.SortedValues) {
\t\t\t\treturn false
\t\t\t}
\t\t}
\t\treturn true
\t}

\tif err := quick.Check(f, &quick.Config{MaxCount: 100}); err != nil {
\t\tt.Error(err)
\t}
}

func TestMigrateLogic(t *testing.T) {
\tinput := []Legacy{
\t\t{ID: 1, Data: "X", Values: []int{3, 1}},
\t\t{ID: 1, Data: "Y", Values: []int{2}},
\t}
\texpected := []Modern{
\t\t{ID: 1, MergedData: "XY", SortedValues: []int{1, 2, 3}},
\t}

\tout := Migrate(input)
\tif !reflect.DeepEqual(out, expected) {
\t\tt.Fatalf("Expected %v, got %v", expected, out)
\t}
}
'''


def run(cmd, cwd=MIGRATOR_DIR):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def expected_migration(records):
    grouped = {}
    for record in records:
        item = grouped.setdefault(record["id"], {"id": record["id"], "merged_data": "", "sorted_values": []})
        item["merged_data"] += record["data"]
        item["sorted_values"].extend(record["values"])
    result = []
    for ident in sorted(grouped):
        item = grouped[ident]
        item["sorted_values"].sort()
        result.append(item)
    return result


def test_test_file_was_not_modified():
    path = MIGRATOR_DIR / "migrate_test.go"
    assert path.is_file(), "migrate_test.go was deleted"
    assert path.read_text() == EXPECTED_MIGRATE_TEST, "migrate_test.go was modified"


def test_go_build_succeeds():
    result = run(["go", "build"])
    assert result.returncode == 0, f"go build failed with error:\n{result.stderr}"


def test_go_test_succeeds():
    result = run(["go", "test"])
    assert result.returncode == 0, f"go test failed with error:\n{result.stderr}\n{result.stdout}"


def test_migrate_on_hidden_randomized_inputs():
    hidden_test = r'''package main

import (
    "math/rand"
    "reflect"
    "sort"
    "testing"
    "time"
)

func TestVerifierRandomizedMigration(t *testing.T) {
    rng := rand.New(rand.NewSource(time.Now().UnixNano()))
    for trial := 0; trial < 250; trial++ {
        n := 1 + rng.Intn(80)
        records := make([]Legacy, n)
        expectedByID := make(map[int]*Modern)

        for i := range records {
            id := rng.Intn(17) - 8
            data := string(rune('a' + rng.Intn(26)))
            values := make([]int, rng.Intn(12))
            for j := range values {
                values[j] = rng.Intn(401) - 200
            }
            records[i] = Legacy{ID: id, Data: data, Values: values}

            if expectedByID[id] == nil {
                expectedByID[id] = &Modern{ID: id}
            }
            expectedByID[id].MergedData += data
            expectedByID[id].SortedValues = append(expectedByID[id].SortedValues, values...)
        }

        ids := make([]int, 0, len(expectedByID))
        for id := range expectedByID {
            ids = append(ids, id)
        }
        sort.Ints(ids)
        expected := make([]Modern, 0, len(ids))
        for _, id := range ids {
            item := expectedByID[id]
            sort.Ints(item.SortedValues)
            expected = append(expected, *item)
        }

        got := Migrate(records)
        if !reflect.DeepEqual(got, expected) {
            t.Fatalf("trial %d: expected %#v, got %#v for input %#v", trial, expected, got, records)
        }
    }
}
'''
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        production_files = list(MIGRATOR_DIR.glob("*.go"))
        production_files = [p for p in production_files if not p.name.endswith("_test.go")]
        assert any(p.name == "migrate.go" for p in production_files), "migrate.go does not exist"
        for source in production_files:
            shutil.copy2(source, td_path / source.name)
        for module_file in ("go.mod", "go.sum"):
            source = MIGRATOR_DIR / module_file
            if source.exists():
                shutil.copy2(source, td_path / module_file)
        (td_path / "verifier_migrate_test.go").write_text(hidden_test)
        result = run(["go", "test", "-run", "^TestVerifierRandomizedMigration$", "-count=1"], cwd=td_path)
        assert result.returncode == 0, f"Migrate failed hidden randomized tests:\n{result.stdout}\n{result.stderr}"


def test_built_migrator_handles_derived_inputs():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        binary = td_path / "migrator"
        result = run(["go", "build", "-o", str(binary), "."])
        assert result.returncode == 0, f"building migrator executable failed:\n{result.stderr}"

        for trial in range(40):
            records = []
            for _ in range(rng.randrange(1, 60)):
                records.append({
                    "id": rng.randrange(-10, 11),
                    "data": chr(ord("A") + rng.randrange(26)),
                    "values": [rng.randrange(-500, 501) for _ in range(rng.randrange(0, 12))],
                })
            input_path = td_path / f"input-{trial}.json"
            output_path = td_path / f"output-{trial}.json"
            input_path.write_text(json.dumps(records))
            result = subprocess.run(
                [str(binary), str(input_path), str(output_path)],
                cwd=MIGRATOR_DIR,
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0, f"migrator failed on trial {trial}:\n{result.stderr}"
            assert output_path.is_file(), f"migrator did not create output on trial {trial}"
            try:
                actual = json.loads(output_path.read_text())
            except json.JSONDecodeError as exc:
                pytest.fail(f"migrator produced invalid JSON on trial {trial}: {exc}")
            assert actual == expected_migration(records), f"incorrect executable output on trial {trial}"


def test_modern_json_exists_and_correct():
    modern_json_path = MIGRATOR_DIR / "modern.json"
    assert modern_json_path.is_file(), f"{modern_json_path} does not exist."

    try:
        data = json.loads(modern_json_path.read_text())
    except json.JSONDecodeError:
        pytest.fail("modern.json is not valid JSON.")

    assert isinstance(data, list), "modern.json should contain a JSON array."

    id_1_records = [r for r in data if r.get("id") == 1]
    assert len(id_1_records) == 1, "There should be exactly one merged record for ID 1."
    record_1 = id_1_records[0]
    assert "merged_data" in record_1, "Missing merged_data in modern.json record."
    assert set(record_1["merged_data"]) == set("AC"), "merged_data for ID 1 should contain 'A' and 'C'."
    assert record_1["merged_data"] == "AC", "merged_data for ID 1 must preserve input order."
    assert "sorted_values" in record_1, "Missing sorted_values in modern.json record."
    assert record_1["sorted_values"] == [1, 2, 5, 7, 9], "sorted_values for ID 1 is not correctly merged and sorted."

    id_2_records = [r for r in data if r.get("id") == 2]
    assert len(id_2_records) == 1, "There should be exactly one merged record for ID 2."
    record_2 = id_2_records[0]
    assert record_2["merged_data"] == "B", "merged_data for ID 2 should be 'B'."
    assert record_2["sorted_values"] == [8], "sorted_values for ID 2 is incorrect."

    expected = [
        {"id": 1, "merged_data": "AC", "sorted_values": [1, 2, 5, 7, 9]},
        {"id": 2, "merged_data": "B", "sorted_values": [8]},
    ]
    assert data == expected, "modern.json has missing, extra, or incorrectly ordered records."

    with tempfile.TemporaryDirectory() as td:
        binary = Path(td) / "migrator"
        regenerated = Path(td) / "modern.json"
        result = run(["go", "build", "-o", str(binary), "."])
        assert result.returncode == 0, result.stderr
        result = subprocess.run(
            [str(binary), str(MIGRATOR_DIR / "legacy.json"), str(regenerated)],
            cwd=MIGRATOR_DIR,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"migrator could not process legacy.json:\n{result.stderr}"
        assert json.loads(regenerated.read_text()) == data, "modern.json does not match the built migrator's output."


def test_migration_diff_exists_and_valid():
    diff_path = MIGRATOR_DIR / "migration.diff"
    assert diff_path.is_file(), f"{diff_path} does not exist."
    diff_content = diff_path.read_text()
    assert len(diff_content.strip()) > 0, "migration.diff is empty."

    lines = diff_content.splitlines()
    has_minus = any(line.startswith("--- ") for line in lines)
    has_plus = any(line.startswith("+++ ") for line in lines)
    assert has_minus and has_plus, "migration.diff does not appear to be a valid unified diff format."
    assert len(lines) >= 3 and lines[0].startswith("--- ") and lines[1].startswith("+++ "), "invalid unified diff headers."

    old_label = lines[0][4:].split("\t", 1)[0].strip()
    new_label = lines[1][4:].split("\t", 1)[0].strip()
    assert os.path.basename(old_label) == "legacy.json", "diff does not identify legacy.json as its old file."
    assert os.path.basename(new_label) == "modern.json", "diff does not identify modern.json as its new file."

    canonical = run(["diff", "-u", "legacy.json", "modern.json"])
    assert canonical.returncode == 1, "legacy.json and modern.json unexpectedly have no differences."
    canonical_lines = canonical.stdout.splitlines()
    assert lines[2:] == canonical_lines[2:], "migration.diff is not the actual unified diff of legacy.json and modern.json."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
