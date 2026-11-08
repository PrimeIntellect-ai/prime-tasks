#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import stat
import subprocess

SCRIPT_PATH = "/home/user/process_sets.sh"
JQ_PATH = "/home/user/bin/jq"
SET_A_PATH = "/home/user/data/set_A.json"
SET_B_PATH = "/home/user/data/set_B.json"
SUM_PATH = "/home/user/sum.txt"
BENCHMARK_PATH = "/home/user/benchmark.txt"
JQ_URL = "https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64"
FINAL_EXPECTED = None


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r", errors="replace") as f:
        source = f.read()
    assert JQ_URL in source, "Script does not contain the required jq 1.6 download URL."
    assert JQ_PATH in source, "Script does not use the required local jq path."
    assert SET_A_PATH in source and SET_B_PATH in source, "Script does not reference both required JSON inputs."
    assert "/usr/bin/time" in source, "Script does not invoke /usr/bin/time."
    assert re.search(r"(?:^|\s)-p(?:\s|$)", source), "Script does not use the required time -p option."


def test_pipeline_execution():
    global FINAL_EXPECTED
    rng = secrets.SystemRandom()

    cases = []
    for _ in range(2):
        shared = set(rng.sample(range(-500000, 500001), 24))
        a_only = set(rng.sample(range(600000, 900001), 31))
        b_only = set(rng.sample(range(-900000, -600000), 29))
        a = list(shared | a_only)
        b = list(shared | b_only)
        # Include duplicates to verify mathematical-set rather than multiset behavior.
        a.extend(list(shared)[:7])
        b.extend(list(shared)[5:14])
        rng.shuffle(a)
        rng.shuffle(b)
        cases.append((a, b, sum(shared)))

    reference_jq = "/tmp/reference-jq-1.6"
    subprocess.run(
        ["/usr/bin/curl", "-fL", "--retry", "2", "-o", reference_jq, JQ_URL],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )

    for a, b, expected in cases:
        with open(SET_A_PATH, "w") as f:
            json.dump({"numbers": a}, f)
        with open(SET_B_PATH, "w") as f:
            json.dump({"numbers": b}, f)

        for path in (SUM_PATH, BENCHMARK_PATH, JQ_PATH):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        result = subprocess.run(
            [SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, (
            f"Script exited with {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(SUM_PATH), f"Output file {SUM_PATH} was not created by the script."
        assert os.path.isfile(BENCHMARK_PATH), f"Benchmark file {BENCHMARK_PATH} was not created by the script."
        with open(SUM_PATH) as f:
            assert f.read().strip() == str(expected), "Script produced an incorrect sum for generated inputs."

        assert os.path.isfile(JQ_PATH), f"jq binary {JQ_PATH} was not created by the script."
        with open(JQ_PATH, "rb") as actual, open(reference_jq, "rb") as reference:
            assert actual.read() == reference.read(), "Local jq is not the required jq 1.6 linux64 download."

        with open(BENCHMARK_PATH) as f:
            benchmark = f.read()
        entries = re.findall(r"(?m)^(real|user|sys)\s+([0-9]+(?:\.[0-9]+)?)\s*$", benchmark)
        assert [name for name, _ in entries] == ["real", "user", "sys"], (
            "benchmark.txt does not contain fresh /usr/bin/time -p output."
        )
        FINAL_EXPECTED = expected


def test_jq_downloaded_and_executable():
    assert os.path.isfile(JQ_PATH), f"jq binary {JQ_PATH} does not exist."
    st = os.stat(JQ_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"jq binary {JQ_PATH} is not executable."
    with open(JQ_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{JQ_PATH} is not a linux executable binary."
    version = subprocess.run(
        [JQ_PATH, "--version"], capture_output=True, text=True, check=True, timeout=10
    ).stdout.strip()
    assert version == "jq-1.6", f"Expected jq-1.6, got {version!r}."


def test_sum_calculation():
    with open(SET_A_PATH, "r") as f:
        set_a = set(json.load(f).get("numbers", []))
    with open(SET_B_PATH, "r") as f:
        set_b = set(json.load(f).get("numbers", []))
    expected_sum = sum(set_a.intersection(set_b))

    assert FINAL_EXPECTED == expected_sum
    assert os.path.isfile(SUM_PATH), f"Output file {SUM_PATH} does not exist."
    with open(SUM_PATH, "r") as f:
        content = f.read().strip()
    assert content == str(expected_sum), f"Expected sum {expected_sum}, but got {content} in {SUM_PATH}."


def test_benchmark_output():
    assert os.path.isfile(BENCHMARK_PATH), f"Benchmark output {BENCHMARK_PATH} does not exist."
    with open(BENCHMARK_PATH, "r") as f:
        content = f.read()
    assert "real" in content, f"'real' not found in {BENCHMARK_PATH}"
    assert "user" in content, f"'user' not found in {BENCHMARK_PATH}"
    assert "sys" in content, f"'sys' not found in {BENCHMARK_PATH}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
