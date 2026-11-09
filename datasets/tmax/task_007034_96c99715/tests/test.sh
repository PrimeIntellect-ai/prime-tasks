#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import secrets
import shutil
import subprocess
import tempfile

import pytest

GO_PROG = pathlib.Path("/home/user/detect_leakage.go")
OUTPUT = pathlib.Path("/home/user/leaked_experiments.txt")
ARTIFACTS = pathlib.Path("/home/user/artifacts")
BINARY = pathlib.Path("/tmp/detect_leakage_verifier")


def run(cmd, timeout):
    return subprocess.run(
        cmd,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def output_lines():
    with OUTPUT.open("r") as f:
        return [line.strip() for line in f if line.strip()]


def test_go_program_exists():
    go_prog_path = "/home/user/detect_leakage.go"
    assert os.path.isfile(go_prog_path), f"Expected Go program at {go_prog_path} is missing."


def test_go_program_builds_and_runs_on_original_artifacts():
    if BINARY.exists():
        BINARY.unlink()
    run(["go", "build", "-o", str(BINARY), str(GO_PROG)], 60)
    assert BINARY.is_file(), "Go source did not produce an executable."

    if OUTPUT.exists():
        OUTPUT.unlink()
    run([str(BINARY)], 20)


def test_output_file_exists():
    output_path = "/home/user/leaked_experiments.txt"
    assert os.path.isfile(output_path), f"Expected output file at {output_path} is missing."


def test_output_file_content():
    output_path = "/home/user/leaked_experiments.txt"
    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = ["EXP-002", "EXP-004"]
    assert lines == expected, f"Output file content does not match expected leaked experiments. Got: {lines}, Expected: {expected}"


def test_dynamic_detection_and_strict_schema():
    token = secrets.token_hex(6).upper()
    leak_z = f"DYN-{token}-Z-LEAK"
    leak_a = f"DYN-{token}-A-LEAK"
    clean = f"DYN-{token}-C-CLEAN"

    extra = f"DYN-{token}-EXTRA"
    missing = f"DYN-{token}-MISSING"
    null_value = f"DYN-{token}-NULL"
    wrong_type = f"DYN-{token}-TYPE"
    trailing = f"DYN-{token}-TRAILING"
    bad_phase = f"DYN-{token}-PHASE"
    duplicate_train = f"DYN-{token}-DUP-TRAIN"
    duplicate_test = f"DYN-{token}-DUP-TEST"
    train_only = f"DYN-{token}-TRAIN-ONLY"
    test_only = f"DYN-{token}-TEST-ONLY"

    base = 1000 + secrets.randbelow(50000)

    def artifact(experiment_id, phase, feature_mean, scaler_val):
        return {
            "experiment_id": experiment_id,
            "phase": phase,
            "feature_mean": feature_mean,
            "scaler_val": scaler_val,
        }

    documents = [
        artifact(leak_z, "train", base + 1.25, base + 1.25),
        artifact(leak_z, "test", base + 8.75, base + 8.75),
        artifact(leak_a, "train", base + 2.5, base + 2.5),
        artifact(leak_a, "test", base + 9.5, base + 9.5),
        artifact(clean, "train", base + 3.125, base + 3.125),
        artifact(clean, "test", base + 11.625, base + 3.125),

        artifact(extra, "train", base + 4.0, base + 4.0),
        {**artifact(extra, "test", base + 12.0, base + 12.0), "unexpected": True},

        artifact(missing, "train", base + 5.0, base + 5.0),
        {"experiment_id": missing, "phase": "test", "feature_mean": 0.0},

        artifact(null_value, "train", base + 6.0, base + 6.0),
        {"experiment_id": null_value, "phase": "test", "feature_mean": 0.0, "scaler_val": None},

        artifact(wrong_type, "train", base + 7.0, base + 7.0),
        {"experiment_id": wrong_type, "phase": "test", "feature_mean": base + 13.0, "scaler_val": str(base + 13.0)},

        artifact(trailing, "train", base + 8.0, base + 8.0),
        artifact(bad_phase, "validation", base + 14.0, base + 14.0),

        artifact(duplicate_train, "train", base + 15.0, base + 15.0),
        artifact(duplicate_train, "train", base + 16.0, base + 16.0),
        artifact(duplicate_train, "test", base + 17.0, base + 17.0),

        artifact(duplicate_test, "train", base + 18.0, base + 18.0),
        artifact(duplicate_test, "test", base + 19.0, base + 19.0),
        artifact(duplicate_test, "test", base + 20.0, base + 20.0),

        artifact(train_only, "train", base + 21.0, base + 21.0),
        artifact(test_only, "test", base + 22.0, base + 22.0),
    ]

    expected = sorted([leak_a, leak_z])
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    with tempfile.TemporaryDirectory() as tmp:
        backup = pathlib.Path(tmp) / "artifacts"
        shutil.copytree(ARTIFACTS, backup)
        try:
            shutil.rmtree(ARTIFACTS)
            ARTIFACTS.mkdir(parents=True)

            for index, document in enumerate(documents):
                name = f"case-{secrets.token_hex(4)}-{index}.json"
                (ARTIFACTS / name).write_text(json.dumps(document), encoding="utf-8")

            trailing_test = artifact(trailing, "test", base + 23.0, base + 23.0)
            (ARTIFACTS / f"trailing-{secrets.token_hex(4)}.json").write_text(
                json.dumps(trailing_test) + "\n{}\n", encoding="utf-8"
            )
            (ARTIFACTS / f"malformed-{secrets.token_hex(4)}.json").write_text(
                '{"experiment_id":', encoding="utf-8"
            )

            OUTPUT.write_text("STALE-SENTINEL\n", encoding="utf-8")
            run([str(BINARY)], 20)

            assert OUTPUT.is_file(), "Program did not create leaked_experiments.txt."
            lines = output_lines()
            assert lines == expected, (
                "Program failed dynamic leakage detection, sorting, exact pairing, or strict schema enforcement. "
                f"Got: {lines}, Expected: {expected}"
            )
        finally:
            if ARTIFACTS.exists():
                shutil.rmtree(ARTIFACTS)
            shutil.copytree(backup, ARTIFACTS)
            if original_output is None:
                if OUTPUT.exists():
                    OUTPUT.unlink()
            else:
                OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
