#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path


def test_fast_filter_exists_and_executable():
    filter_path = Path("/home/user/fast_filter")
    source_path = Path("/home/user/fast_filter.c")
    oracle_path = Path("/app/anomaly_oracle")

    assert filter_path.exists(), "The fast_filter binary does not exist at /home/user/fast_filter."
    assert filter_path.is_file(), "/home/user/fast_filter is not a file."
    assert os.access(filter_path, os.X_OK), "The fast_filter binary is not executable."
    assert source_path.exists() and source_path.is_file(), "The C source does not exist at /home/user/fast_filter.c."
    assert oracle_path.exists() and oracle_path.is_file(), "The anomaly oracle is missing."
    assert filter_path.read_bytes() != oracle_path.read_bytes(), "fast_filter is byte-identical to the supplied oracle."


def oracle_label(oracle_path, sample_path):
    result = subprocess.run(
        [str(oracle_path), str(sample_path)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
    )
    assert result.returncode in (0, 1), f"Oracle failed on generated input with code {result.returncode}."
    return "evil" if result.returncode == 1 else "clean"


def neutral_name(used):
    while True:
        name = f"sample_{secrets.token_hex(12)}.bin"
        if name not in used:
            used.add(name)
            return name


def test_fast_filter_correctness():
    filter_path = Path("/home/user/fast_filter")
    oracle_path = Path("/app/anomaly_oracle")
    evil_corpus_dir = Path("/var/opt/eval_data/evil")
    clean_corpus_dir = Path("/var/opt/eval_data/clean")

    assert evil_corpus_dir.exists() and evil_corpus_dir.is_dir(), "Evil corpus directory missing."
    assert clean_corpus_dir.exists() and clean_corpus_dir.is_dir(), "Clean corpus directory missing."

    evil_files = list(evil_corpus_dir.glob("*.bin"))
    clean_files = list(clean_corpus_dir.glob("*.bin"))
    assert len(evil_files) > 0, "No evil files found in corpus."
    assert len(clean_files) > 0, "No clean files found in corpus."

    with tempfile.TemporaryDirectory() as temp_input, tempfile.TemporaryDirectory() as temp_output:
        input_path = Path(temp_input)
        output_path = Path(temp_output)
        (output_path / "clean").mkdir(parents=True, exist_ok=True)
        (output_path / "evil").mkdir(parents=True, exist_ok=True)

        expected = {}
        used_names = set()

        # Retain the original labeled corpus checks, but remove label-bearing names.
        for label, files in (("evil", evil_files), ("clean", clean_files)):
            for source in files:
                name = neutral_name(used_names)
                data = source.read_bytes()
                assert len(data) == 64 * 4, f"Invalid corpus record size: {source}"
                (input_path / name).write_bytes(data)
                expected[name] = (label, data)

        # Add fresh, unpredictably named records and derive every answer by querying
        # the oracle rather than trusting filenames or a fixed answer list.
        random_bytes = secrets.SystemRandom()
        generated = []
        for i in range(320):
            if i < 180:
                scale = random_bytes.choice((0.05, 0.5, 2.0, 10.0, 50.0, 500.0))
                values = [random_bytes.uniform(-scale, scale) for _ in range(64)]
            elif i < 240:
                values = [0.0] * 64
                for _ in range(random_bytes.randint(1, 8)):
                    values[random_bytes.randrange(64)] = random_bytes.uniform(-100.0, 100.0)
            elif i < 280:
                value = random_bytes.uniform(-20.0, 20.0)
                values = [value] * 64
            else:
                values = [random_bytes.choice((-1.0, 0.0, 1.0)) * random_bytes.uniform(0.0, 25.0) for _ in range(64)]

            name = neutral_name(used_names)
            data = struct.pack("<64f", *values)
            sample = input_path / name
            sample.write_bytes(data)
            generated.append((name, data, sample))

        generated_labels = set()
        for name, data, sample in generated:
            label = oracle_label(oracle_path, sample)
            generated_labels.add(label)
            expected[name] = (label, data)
        assert generated_labels == {"clean", "evil"}, "Randomized oracle corpus did not contain both classes."

        result = subprocess.run(
            [str(filter_path), str(input_path), str(output_path)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"fast_filter exited with non-zero code {result.returncode}. stderr: {result.stderr}"
        )

        benchmark = re.search(r"Processed\s+(\d+)\s+files\s+in\s+([0-9]+(?:\.[0-9]+)?)\s+seconds", result.stdout)
        assert benchmark, "fast_filter did not print the required benchmark line."
        assert int(benchmark.group(1)) == len(expected), "Benchmark line reported the wrong file count."

        expected_paths = {f"{label}/{name}" for name, (label, _) in expected.items()}
        actual_paths = {
            str(path.relative_to(output_path))
            for path in output_path.rglob("*.bin")
        }
        assert actual_paths == expected_paths, (
            f"Output file set differs from expected. Missing: {sorted(expected_paths - actual_paths)[:10]}; "
            f"unexpected: {sorted(actual_paths - expected_paths)[:10]}"
        )

        for name, (label, original_data) in expected.items():
            destination = output_path / label / name
            assert destination.is_file(), f"Missing classified output: {label}/{name}"
            assert not destination.is_symlink(), f"Output is a symlink rather than a copied file: {label}/{name}"
            assert destination.read_bytes() == original_data, f"Output contents were modified for {name}"
            other_label = "clean" if label == "evil" else "evil"
            assert not (output_path / other_label / name).exists(), f"File appeared in both classes: {name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
