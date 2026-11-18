#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import json
import hashlib
import random
import re
import subprocess
import tempfile

HOME = "/home/user"
RAW = f"{HOME}/data/raw_dataset.txt"
CLEANED = f"{HOME}/data/cleaned_dataset.txt"
BENCHMARK = f"{HOME}/data/benchmark.json"
HASHFILE = f"{HOME}/data/reproducibility_hash.txt"


def get_embed(s):
    vec = [0.0] * 16
    for i in range(16):
        acc = sum(ord(c) * (i + 1) for c in s.strip('\n'))
        vec[i] = acc % 100
    norm = math.sqrt(sum(v*v for v in vec))
    if norm > 0:
        vec = [v/norm for v in vec]
    return vec


def dot(v1, v2):
    return sum(x*y for x, y in zip(v1, v2))


def expected_from_lines(lines):
    accepted = []
    kept_lines = []
    for line in lines:
        emb = get_embed(line)
        is_dup = False
        for a_emb in accepted:
            if dot(emb, a_emb) >= 0.90:
                is_dup = True
                break
        if not is_dup:
            accepted.append(emb)
            kept_lines.append(line)
    return kept_lines


def compute_expected_cleaned_data():
    if not os.path.exists(RAW):
        return []
    with open(RAW, "r") as f:
        lines = f.readlines()
    return expected_from_lines(lines)


def run_checked(command, timeout=60):
    return subprocess.run(
        command,
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def validate_benchmark(total, kept):
    with open(BENCHMARK, "r") as f:
        data = json.load(f)
    expected_keys = {"total_lines", "kept_lines", "time_seconds", "throughput_lines_per_sec"}
    assert expected_keys.issubset(data.keys())
    assert data["total_lines"] == total
    assert data["kept_lines"] == kept
    for key in ("time_seconds", "throughput_lines_per_sec"):
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool)
        assert math.isfinite(value) and value >= 0
    if total > 0:
        assert data["time_seconds"] > 0
        expected_throughput = total / data["time_seconds"]
        assert data["throughput_lines_per_sec"] > 0
        assert math.isclose(data["throughput_lines_per_sec"], expected_throughput, rel_tol=0.20, abs_tol=1e-6)


def exercise_cleaner(executable, lines):
    with open(RAW, "w") as f:
        f.writelines(lines)
    for path in (CLEANED, BENCHMARK):
        if os.path.exists(path):
            os.remove(path)

    run_checked([executable])
    assert os.path.isfile(CLEANED), "cleaner did not create cleaned_dataset.txt"
    assert os.path.isfile(BENCHMARK), "cleaner did not create benchmark.json"

    expected = expected_from_lines(lines)
    with open(CLEANED, "r") as f:
        actual = f.readlines()
    assert actual == expected, "The executed C++ cleaner produced incorrect filtered data."
    validate_benchmark(len(lines), len(expected))


def test_pipeline_build_and_executed_cleaner():
    required_inputs = [
        f"{HOME}/cleaner.cpp",
        f"{HOME}/Makefile",
        f"{HOME}/run_pipeline.sh",
    ]
    for path in required_inputs:
        assert os.path.isfile(path), f"Expected file {path} is missing."
    assert os.access(f"{HOME}/run_pipeline.sh", os.X_OK), "run_pipeline.sh is not executable"

    with open(f"{HOME}/Makefile", "r") as f:
        makefile = f.read()
    uncommented_makefile = "\n".join(line.split("#", 1)[0] for line in makefile.splitlines())
    assert "-O3" in uncommented_makefile, "Makefile does not use the required -O3 optimization flag."

    with open(f"{HOME}/run_pipeline.sh", "r") as f:
        script = f.read()
    active_script = "\n".join(line.split("#", 1)[0] for line in script.splitlines())
    assert re.search(r"(^|[;&|\s])(?:/usr/bin/)?make(?:\s|$)", active_script), "run_pipeline.sh does not invoke make."
    assert "./cleaner" in active_script, "run_pipeline.sh does not execute ./cleaner."

    with open(RAW, "rb") as f:
        original_raw = f.read()

    try:
        for path in (f"{HOME}/cleaner", CLEANED, BENCHMARK, HASHFILE):
            if os.path.exists(path):
                os.remove(path)

        run_checked([f"{HOME}/run_pipeline.sh"])
        for path in (f"{HOME}/cleaner", CLEANED, BENCHMARK, HASHFILE):
            assert os.path.isfile(path), f"run_pipeline.sh did not create {path}"
        with open(f"{HOME}/cleaner", "rb") as f:
            assert f.read(4) == b"\x7fELF", "cleaner is not a compiled native executable."

        dry_run = run_checked(["make", "-Bn", "cleaner"])
        build_commands = dry_run.stdout + dry_run.stderr
        assert "-O3" in build_commands, "The cleaner build command does not use -O3."
        assert "cleaner.cpp" in build_commands, "Make does not compile cleaner.cpp."

        os.remove(f"{HOME}/cleaner")
        run_checked(["make", "-B", "cleaner"])
        assert os.path.isfile(f"{HOME}/cleaner") and os.access(f"{HOME}/cleaner", os.X_OK)
        with open(f"{HOME}/cleaner", "rb") as f:
            assert f.read(4) == b"\x7fELF", "Make did not produce a compiled cleaner executable."

        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        bases = [
            "The quick brown fox jumps over the lazy dog.",
            "Data science is an interdisciplinary field.",
            "C++ is a high-performance programming language.",
            "Machine learning models require large datasets.",
            "A custom embedding space can be simulated easily.",
        ]
        challenge = ["\n", "\n", "single document\n", "single document\n"]
        alphabet = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        for i in range(73):
            base = rng.choice(bases)
            noise = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 14)))
            challenge.append(f"{base}{noise}{i}\n")

        exercise_cleaner(f"{HOME}/cleaner", challenge)

        with tempfile.TemporaryDirectory() as td:
            independently_compiled = os.path.join(td, "cleaner_from_source")
            run_checked(["g++", "-O3", f"{HOME}/cleaner.cpp", "-o", independently_compiled])
            with open(independently_compiled, "rb") as f:
                assert f.read(4) == b"\x7fELF"
            second_challenge = list(reversed(challenge[2:])) + ["    \n", "xyz\n", "xyz\n"]
            exercise_cleaner(independently_compiled, second_challenge)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
        run_checked([f"{HOME}/run_pipeline.sh"])


def test_files_exist():
    expected_files = [
        "/home/user/cleaner.cpp",
        "/home/user/Makefile",
        "/home/user/run_pipeline.sh",
        "/home/user/data/cleaned_dataset.txt",
        "/home/user/data/benchmark.json",
        "/home/user/data/reproducibility_hash.txt"
    ]
    for f in expected_files:
        assert os.path.isfile(f), f"Expected file {f} is missing."


def test_run_pipeline_executable():
    path = "/home/user/run_pipeline.sh"
    assert os.access(path, os.X_OK), f"{path} is not executable."


def test_cleaned_dataset_content():
    expected_lines = compute_expected_cleaned_data()
    path = "/home/user/data/cleaned_dataset.txt"
    with open(path, "r") as f:
        actual_lines = f.readlines()
    assert actual_lines == expected_lines, "The contents of cleaned_dataset.txt do not match the expected output based on the embedding and filtering logic."


def test_benchmark_json():
    expected_lines = compute_expected_cleaned_data()
    path = "/home/user/data/benchmark.json"
    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "benchmark.json is not a valid JSON file."

    expected_keys = {"total_lines", "kept_lines", "time_seconds", "throughput_lines_per_sec"}
    assert expected_keys.issubset(data.keys()), f"benchmark.json is missing one or more required keys: {expected_keys - data.keys()}"
    assert data["total_lines"] == 500, f"Expected total_lines to be 500, got {data['total_lines']}"
    assert data["kept_lines"] == len(expected_lines), f"Expected kept_lines to be {len(expected_lines)}, got {data['kept_lines']}"
    assert isinstance(data["time_seconds"], (int, float)), "time_seconds must be a number."
    assert isinstance(data["throughput_lines_per_sec"], (int, float)), "throughput_lines_per_sec must be a number."


def test_reproducibility_hash():
    cleaned_path = "/home/user/data/cleaned_dataset.txt"
    hash_path = "/home/user/data/reproducibility_hash.txt"
    with open(cleaned_path, "rb") as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()
    with open(hash_path, "r") as f:
        actual_hash = f.read().strip().split()[0]
    assert actual_hash == expected_hash, f"The hash in reproducibility_hash.txt ({actual_hash}) does not match the actual SHA-256 hash of cleaned_dataset.txt ({expected_hash})."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
