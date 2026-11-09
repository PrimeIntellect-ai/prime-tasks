#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import shlex
import subprocess
import uuid
import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/process.rs"
DATASET = f"{HOME}/embeddings.csv"
BINARY = f"{HOME}/process"
SHUFFLED = f"{HOME}/shuffled.csv"
REPRO = f"{HOME}/test_repro.sh"


def run_checked(argv, timeout=20, env=None):
    return subprocess.run(
        argv,
        capture_output=True,
        text=True,
        check=True,
        timeout=timeout,
        env=env,
    )


def make_case(candidate_count=12):
    rng = random.SystemRandom()
    while True:
        target = [rng.randint(-100, 100) for _ in range(5)]
        candidates = []
        for _ in range(candidate_count):
            values = [rng.randint(-100, 100) for _ in range(5)]
            candidates.append((f"case_{uuid.uuid4().hex}", values))

        tx = target[0] + target[1]
        ty = target[2] + target[3] + target[4]
        distances = []
        for ident, values in candidates:
            x = values[0] + values[1]
            y = values[2] + values[3] + values[4]
            distances.append(((x - tx) ** 2 + (y - ty) ** 2, ident))

        minimum = min(distance for distance, _ in distances)
        winners = [ident for distance, ident in distances if distance == minimum]
        if len(winners) == 1:
            break

    rows = [("target_run", target)] + candidates
    rng.shuffle(rows)
    text = "".join(
        ident + "," + ",".join(str(value / 10.0) for value in values) + "\n"
        for ident, values in rows
    )
    return text, winners[0]


def test_closest_txt_content():
    closest_path = "/home/user/closest.txt"
    assert os.path.isfile(closest_path), f"File {closest_path} is missing."

    with open(closest_path, "r") as f:
        content = f.read().strip()

    assert content == "run_4", f"Expected 'run_4' in {closest_path}, but got '{content}'."


def test_process_rs_exists():
    process_rs_path = "/home/user/process.rs"
    assert os.path.isfile(process_rs_path), f"Rust source file {process_rs_path} is missing."


def test_repro_sh_exists_and_passes():
    repro_sh_path = "/home/user/test_repro.sh"
    assert os.path.isfile(repro_sh_path), f"Bash script {repro_sh_path} is missing."

    try:
        result = subprocess.run(
            ["bash", repro_sh_path],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        output = result.stdout.strip()
        assert "PASS" in output, f"Expected 'PASS' in the output of {repro_sh_path}, but got '{output}'."
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script {repro_sh_path} failed to execute. Error: {e.stderr}")


def test_rust_program_compiles_and_implements_mapping(tmp_path):
    compiled = tmp_path / "process_under_test"
    result = run_checked(["rustc", SOURCE, "-o", str(compiled)], timeout=30)
    assert compiled.is_file(), f"rustc did not create {compiled}: {result.stderr}"

    original = run_checked([str(compiled), DATASET])
    assert original.stdout.strip() == "run_4"
    assert original.stdout == "run_4\n" or original.stdout == "run_4"

    for index in range(8):
        csv_text, expected = make_case()
        case_path = tmp_path / f"case_{index}.csv"
        case_path.write_text(csv_text)

        result = run_checked([str(compiled), str(case_path)])
        assert result.stdout.strip() == expected, (
            f"Wrong nearest experiment for generated case {index}: "
            f"expected {expected!r}, got {result.stdout!r}"
        )
        assert result.stdout == expected + "\n" or result.stdout == expected, (
            "The Rust program must print only the closest experiment ID."
        )

        lines = csv_text.splitlines()
        random.SystemRandom().shuffle(lines)
        shuffled_path = tmp_path / f"case_{index}_shuffled.csv"
        shuffled_path.write_text("\n".join(lines) + "\n")
        shuffled_result = run_checked([str(compiled), str(shuffled_path)])
        assert shuffled_result.stdout.strip() == expected


def test_repro_script_performs_pipeline_on_fresh_data():
    original_dataset = open(DATASET, "rb").read()
    original_source = open(SOURCE, "rb").read()
    challenge, expected = make_case(candidate_count=15)

    try:
        with open(DATASET, "w") as f:
            f.write(challenge)
        for path in (BINARY, SHUFFLED):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        env = os.environ.copy()
        env["PS4"] = "+ "
        result = subprocess.run(
            ["bash", "-x", REPRO],
            capture_output=True,
            text=True,
            timeout=40,
            env=env,
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "PASS", (
            f"The reproducibility script must print exactly PASS on success, got {result.stdout!r}"
        )
        assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
            "test_repro.sh did not create the required executable /home/user/process"
        )
        assert os.path.isfile(SHUFFLED), "test_repro.sh did not create /home/user/shuffled.csv"
        assert open(SOURCE, "rb").read() == original_source, "test_repro.sh modified process.rs"

        original_lines = challenge.splitlines()
        shuffled_lines = open(SHUFFLED).read().splitlines()
        assert collections.Counter(shuffled_lines) == collections.Counter(original_lines), (
            "shuffled.csv is not a line-wise shuffle of embeddings.csv"
        )

        first = run_checked([BINARY, DATASET])
        second = run_checked([BINARY, SHUFFLED])
        assert first.stdout.strip() == expected
        assert second.stdout.strip() == expected
        assert first.stdout == second.stdout

        traced = []
        for line in result.stderr.splitlines():
            stripped = line.lstrip()
            if not stripped.startswith("+"):
                continue
            command = stripped.lstrip("+").strip()
            try:
                words = shlex.split(command)
            except ValueError:
                continue
            while words and "=" in words[0] and not words[0].startswith("/"):
                words.pop(0)
            if words:
                traced.append(words)

        assert any(os.path.basename(words[0]) == "rustc" for words in traced), (
            "test_repro.sh did not execute rustc"
        )
        assert any(os.path.basename(words[0]) == "shuf" for words in traced), (
            "test_repro.sh did not execute shuf"
        )
        assert any(words[0] == BINARY and DATASET in words[1:] for words in traced), (
            "test_repro.sh did not run /home/user/process on embeddings.csv"
        )
        assert any(words[0] == BINARY and SHUFFLED in words[1:] for words in traced), (
            "test_repro.sh did not run /home/user/process on shuffled.csv"
        )
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
