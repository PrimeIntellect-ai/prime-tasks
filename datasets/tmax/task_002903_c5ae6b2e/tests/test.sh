#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile
import pytest

CPP_SOURCE = "/home/user/compute_dist.cpp"
CPP_BINARY = "/home/user/compute_dist"
BASH_SCRIPT = "/home/user/run_pipeline.sh"
INCOMING = "/home/user/incoming"
OUTGOING = "/home/user/outgoing"


def levenshtein(a, b):
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        current = [i]
        for j, cb in enumerate(b, 1):
            current.append(min(
                current[-1] + 1,
                previous[j] + 1,
                previous[j - 1] + (ca != cb),
            ))
        previous = current
    return previous[-1]


def expected_lines(pairs):
    return [f"{a},{b},{levenshtein(a, b)}" for a, b in pairs]


def run_compute(binary, pairs):
    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, "input.csv")
        output_path = os.path.join(td, "output.csv")
        with open(input_path, "w", encoding="ascii") as f:
            for a, b in pairs:
                f.write(f"{a},{b}\n")
        result = subprocess.run(
            [binary, input_path, output_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr
        assert os.path.isfile(output_path), "compute_dist did not create its output file"
        with open(output_path, encoding="ascii") as f:
            actual = f.read().splitlines()
        assert actual == expected_lines(pairs)


def test_cron_job_exists():
    try:
        result = subprocess.run(['crontab', '-l'], capture_output=True, text=True, check=True)
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab or crontab is empty.")

    expected_cron = "*/15 * * * * /home/user/run_pipeline.sh"
    found = any(expected_cron in line for line in crontab_content.splitlines())
    assert found, f"Cron job '{expected_cron}' not found in crontab."
    active_lines = [line.strip() for line in crontab_content.splitlines()
                    if line.strip() and not line.lstrip().startswith('#')]
    assert expected_cron in active_lines, f"Cron job '{expected_cron}' is not an active exact entry."


def test_executables_exist():
    assert os.path.isfile(CPP_SOURCE), f"{CPP_SOURCE} does not exist."
    assert os.path.isfile(CPP_BINARY), f"{CPP_BINARY} does not exist."
    assert os.access(CPP_BINARY, os.X_OK), f"{CPP_BINARY} is not executable."
    assert os.path.isfile(BASH_SCRIPT), f"{BASH_SCRIPT} does not exist."
    assert os.access(BASH_SCRIPT, os.X_OK), f"{BASH_SCRIPT} is not executable."


def test_source_uses_parallel_processing_and_builds():
    with open(CPP_SOURCE, encoding="utf-8") as f:
        source = f.read()

    # Ignore comments and ordinary string literals when looking for concurrency APIs.
    checked = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    checked = re.sub(r'"(?:\\.|[^"\\])*"', '""', checked)
    parallel_patterns = [
        r'#\s*pragma\s+omp\s+parallel',
        r'\bstd\s*::\s*thread\b',
        r'\bstd\s*::\s*async\s*\(',
        r'\bpthread_create\s*\(',
        r'\bstd\s*::\s*execution\s*::\s*par(?:_unseq)?\b',
    ]
    assert any(re.search(pattern, checked) for pattern in parallel_patterns), \
        "compute_dist.cpp does not use a recognized parallel-processing mechanism"

    rebuilt = tempfile.NamedTemporaryFile(prefix="compute_dist_rebuilt_", delete=False)
    rebuilt.close()
    try:
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", "-fopenmp", "-pthread", CPP_SOURCE, "-o", rebuilt.name],
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, f"compute_dist.cpp does not compile:\n{result.stderr}"
        rng = random.Random(917263)
        alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        pairs = []
        for _ in range(37):
            a = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 35)))
            b = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 35)))
            pairs.append((a, b))
        pairs += [("same", "same"), ("a", "bbbbbbbb"), ("Case", "case")]
        run_compute(rebuilt.name, pairs)
        run_compute(CPP_BINARY, pairs)
    finally:
        if os.path.exists(rebuilt.name):
            os.unlink(rebuilt.name)


def test_pipeline_execution():
    os.makedirs(INCOMING, exist_ok=True)
    os.makedirs(OUTGOING, exist_ok=True)
    for directory in (INCOMING, OUTGOING):
        for name in os.listdir(directory):
            path = os.path.join(directory, name)
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    batches = {
        "batch1.csv": [("kitten", "sitting"), ("flaw", "lawn"), ("intent", "execution")],
        "batch2.csv": [("rosettacode", "raisethysword"), ("distance", "difference"), ("parallel", "unparallel")],
    }

    rng = random.Random(481516)
    alphabet = "abcdefghijklmnopqrstuvwxyz"
    generated = []
    for _ in range(29):
        a = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 28)))
        b = ''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 28)))
        generated.append((a, b))
    batches["generated.csv"] = generated

    for filename, pairs in batches.items():
        with open(os.path.join(INCOMING, filename), "w", encoding="ascii") as f:
            for a, b in pairs:
                f.write(f"{a},{b}\n")

    try:
        subprocess.run([BASH_SCRIPT], check=True, capture_output=True, text=True, timeout=60)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of {BASH_SCRIPT} failed: {e.stderr}")

    remaining_files = os.listdir(INCOMING)
    assert len(remaining_files) == 0, f"{INCOMING} should be empty after running the pipeline, found: {remaining_files}"

    out_batch1 = os.path.join(OUTGOING, "batch1.csv")
    out_batch2 = os.path.join(OUTGOING, "batch2.csv")
    assert os.path.isfile(out_batch1), f"{out_batch1} was not created."
    assert os.path.isfile(out_batch2), f"{out_batch2} was not created."

    with open(out_batch1, encoding="ascii") as f:
        content1 = f.read()
    assert "kitten,sitting,3" in content1
    assert "flaw,lawn,2" in content1
    assert "intent,execution,5" in content1

    with open(out_batch2, encoding="ascii") as f:
        content2 = f.read()
    assert "rosettacode,raisethysword,8" in content2
    assert "distance,difference,5" in content2
    assert "parallel,unparallel,2" in content2

    assert sorted(os.listdir(OUTGOING)) == sorted(batches)
    for filename, pairs in batches.items():
        with open(os.path.join(OUTGOING, filename), encoding="ascii") as f:
            assert f.read().splitlines() == expected_lines(pairs)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
