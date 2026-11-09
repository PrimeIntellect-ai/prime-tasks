#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import multiprocessing
import os
import shutil
import subprocess
import tempfile
import unicodedata

import pytest

WORKSPACE = "/home/user/workspace"
GO_SOURCE = os.path.join(WORKSPACE, "clean_data.go")
OUTPUT = os.path.join(WORKSPACE, "output.jsonl")
BINARY = "/tmp/clean_data_submission"


def build_submission():
    result = subprocess.run(
        ["go", "build", "-o", BINARY, GO_SOURCE],
        cwd=WORKSPACE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f"clean_data.go did not compile:\n{result.stdout}{result.stderr}"


def run_submission(timeout=30):
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    try:
        result = subprocess.run(
            [BINARY],
            cwd=WORKSPACE,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The Go program timed out while processing the review files.")
    assert result.returncode == 0, f"The Go program failed:\n{result.stdout}{result.stderr}"
    assert os.path.isfile(OUTPUT), f"Expected output file at {OUTPUT} is missing."


def read_output():
    records = []
    with open(OUTPUT, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON line found in {OUTPUT}: {line}")
    return records


def test_go_file_exists_and_uses_goroutines():
    assert os.path.isfile(GO_SOURCE), f"Expected Go source file at {GO_SOURCE} is missing."

    with open(GO_SOURCE, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "go " in content, "The Go program must use Goroutines (the 'go' keyword was not found)."

    # Require an actual Go statement in the parsed source, rather than a comment or string.
    checker = r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
)
func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(2) }
    found := false
    ast.Inspect(f, func(n ast.Node) bool {
        if _, ok := n.(*ast.GoStmt); ok { found = true }
        return true
    })
    if !found { os.Exit(1) }
}
'''
    checker_path = "/tmp/check_goroutine.go"
    with open(checker_path, "w", encoding="utf-8") as f:
        f.write(checker)
    result = subprocess.run(
        ["go", "run", checker_path, GO_SOURCE],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "The Go program must contain an actual goroutine launch statement."


def test_output_jsonl_exists_and_correct():
    build_submission()
    run_submission()

    expected_records = [
        {"user_id": "1", "username": "alice_smith", "country": "UK", "normalized_review": "Good product!"},
        {"user_id": "2", "username": "taro_yamada", "country": "JPN", "normalized_review": "スゴイガ"},
        {"user_id": "3", "username": "helene_d", "country": "FRA", "normalized_review": "Très bien"},
        {"user_id": "4", "username": "ahmed_m", "country": "EGY", "normalized_review": "ممتاز"},
    ]

    for rec in expected_records:
        rec["normalized_review"] = unicodedata.normalize("NFC", rec["normalized_review"])

    actual_records = read_output()
    assert len(actual_records) == len(expected_records), f"Expected {len(expected_records)} records, but found {len(actual_records)}."

    for expected in expected_records:
        assert expected in actual_records, f"Expected record {expected} not found in output.jsonl. Make sure the text is NFC normalized."

    for actual in actual_records:
        review = actual.get("normalized_review", "")
        assert review == unicodedata.normalize("NFC", review), f"Review text '{review}' is not NFC normalized."


def feed_fifos(paths, payloads):
    descriptors = []
    try:
        # Open every FIFO before writing to any one. A sequential reader blocks on
        # its first file, while concurrent per-file readers allow all opens to finish.
        for path in paths:
            descriptors.append(os.open(path, os.O_WRONLY))
        for fd, payload in zip(descriptors, payloads):
            data = payload.encode("utf-8")
            while data:
                written = os.write(fd, data)
                data = data[written:]
    finally:
        for fd in descriptors:
            os.close(fd)


def test_dynamic_inputs_and_parallel_file_reads():
    metadata_path = os.path.join(WORKSPACE, "metadata.csv")
    original_metadata = open(metadata_path, "rb").read()
    original_reviews = {}
    for path in glob.glob(os.path.join(WORKSPACE, "reviews_*.csv")):
        if os.path.isfile(path):
            original_reviews[os.path.basename(path)] = open(path, "rb").read()

    fifo_paths = []
    feeder = None
    try:
        for path in glob.glob(os.path.join(WORKSPACE, "reviews_*.csv")):
            os.unlink(path)

        nonce = os.urandom(8).hex()
        ids = [f"dyn-{nonce}-{i}" for i in range(1, 6)]
        metadata = (
            "user_id,username,country\n"
            f"{ids[0]},user_{nonce}_a,CAN\n"
            f"{ids[1]},user_{nonce}_b,ESP\n"
            f"{ids[2]},user_{nonce}_c,KOR\n"
            f"{ids[3]},metadata_only,NZL\n"
        )
        with open(metadata_path, "w", encoding="utf-8", newline="") as f:
            f.write(metadata)

        review_a = unicodedata.normalize("NFD", "Café déjà vu")
        review_b = unicodedata.normalize("NFD", "El niño está aquí")
        review_c = unicodedata.normalize("NFD", "한글 테스트")
        payloads = [
            "user_id,review_text\n" + f"{ids[0]},{review_a}\n{ids[4]},unmatched review\n",
            "user_id,review_text\n" + f"{ids[1]},{review_b}\n{ids[2]},{review_c}\n",
        ]

        fifo_paths = [
            os.path.join(WORKSPACE, "reviews_dynamic_a.csv"),
            os.path.join(WORKSPACE, "reviews_dynamic_b.csv"),
        ]
        for path in fifo_paths:
            os.mkfifo(path)

        feeder = multiprocessing.Process(target=feed_fifos, args=(fifo_paths, payloads))
        feeder.start()
        run_submission(timeout=15)
        feeder.join(timeout=5)
        assert feeder.exitcode == 0, "The review-file feeder did not complete. Files were not read concurrently."

        expected = [
            {"user_id": ids[0], "username": f"user_{nonce}_a", "country": "CAN", "normalized_review": unicodedata.normalize("NFC", review_a)},
            {"user_id": ids[1], "username": f"user_{nonce}_b", "country": "ESP", "normalized_review": unicodedata.normalize("NFC", review_b)},
            {"user_id": ids[2], "username": f"user_{nonce}_c", "country": "KOR", "normalized_review": unicodedata.normalize("NFC", review_c)},
        ]
        actual = read_output()
        assert len(actual) == len(expected), f"Expected {len(expected)} dynamically derived records, found {len(actual)}."
        for record in actual:
            assert set(record.keys()) == {"user_id", "username", "country", "normalized_review"}, "Output objects must have exactly the required keys."
            assert record["normalized_review"] == unicodedata.normalize("NFC", record["normalized_review"]), "A dynamically supplied review was not NFC normalized."
        for record in expected:
            assert record in actual, f"Expected dynamically derived joined record not found: {record}"
    finally:
        if feeder is not None and feeder.is_alive():
            feeder.terminate()
            feeder.join(timeout=5)
        for path in glob.glob(os.path.join(WORKSPACE, "reviews_*.csv")):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        with open(metadata_path, "wb") as f:
            f.write(original_metadata)
        for name, data in original_reviews.items():
            with open(os.path.join(WORKSPACE, name), "wb") as f:
                f.write(data)
        # Leave the workspace in the requested final state for the original fixtures.
        run_submission(timeout=30)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
