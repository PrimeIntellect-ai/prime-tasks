#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import time
import pytest

PIPELINE_DIR = "/home/user/pipeline"
SEQUENCES_FILE = os.path.join(PIPELINE_DIR, "sequences.txt")
SLOWEST_STEP_FILE = "/home/user/slowest_step.txt"
GRAPH_OUTPUT_FILE = os.path.join(PIPELINE_DIR, "graph_output.txt")
FILTERED_SEQ_FILE = os.path.join(PIPELINE_DIR, "filtered_sequences.txt")
PRIMERS_FILE = os.path.join(PIPELINE_DIR, "primers.txt")
ORCHESTRATOR = os.path.join(PIPELINE_DIR, "orchestrator.sh")
STEP3 = os.path.join(PIPELINE_DIR, "step3_graph_build.sh")

ORIGINAL_SLOW_STEP = '''#!/bin/bash
> graph_output.txt
cat filtered_sequences.txt | while read seq1; do
    cat filtered_sequences.txt | while read seq2; do
        if [ "$seq1" != "$seq2" ]; then
            suffix="${seq1: -4}"
            prefix="${seq2:0:4}"
            if [ "$suffix" == "$prefix" ]; then
                echo "$seq1 -> $seq2" >> graph_output.txt
            fi
        fi
    done
done
'''


def canonical_sequences():
    program = r'''BEGIN {
        srand(42);
        chars="ACGT";
        for(i=1; i<=400; i++) {
            seq="";
            for(j=1; j<=20; j++) {
                seq = seq substr(chars, int(rand()*4)+1, 1);
            }
            print seq;
        }
    }'''
    result = subprocess.run(
        ["awk", program], text=True, capture_output=True, check=True
    )
    return result.stdout + (
        "ACGTACGTACGTACGTACGT\n"
        "ACGTGGGGGGGGGGGGGGGG\n"
        "TTTTTTTTTTTTTTTTACGT\n"
    )


@pytest.fixture(scope="session", autouse=True)
def run_pipeline_fresh():
    expected_source = canonical_sequences()
    with open(SEQUENCES_FILE, "r") as f:
        assert f.read() == expected_source, "sequences.txt was modified"

    for path in (ORCHESTRATOR, STEP3):
        assert os.path.isfile(path) and not os.path.islink(path), f"{path} must be a regular file"
        assert os.access(path, os.X_OK), f"{path} is not executable"

    with open(STEP3, "r") as f:
        assert f.read() != ORIGINAL_SLOW_STEP, "step3_graph_build.sh was not optimized"

    # Remove stale agent-supplied results so correctness is checked on a fresh run.
    for path in (GRAPH_OUTPUT_FILE, FILTERED_SEQ_FILE, PRIMERS_FILE):
        if os.path.lexists(path):
            assert not os.path.isdir(path), f"Expected an output file, but {path} is a directory"
            os.unlink(path)

    start = time.monotonic()
    try:
        result = subprocess.run(
            [ORCHESTRATOR], cwd=PIPELINE_DIR, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1.0
        )
    except subprocess.TimeoutExpired:
        pytest.fail("orchestrator.sh did not finish in under 1 second")
    elapsed = time.monotonic() - start

    assert result.returncode == 0, (
        f"orchestrator.sh failed with exit code {result.returncode}: {result.stderr}"
    )
    assert elapsed < 1.0, f"orchestrator.sh took {elapsed:.3f} seconds; expected under 1 second"

    with open(SEQUENCES_FILE, "r") as f:
        assert f.read() == expected_source, "orchestrator.sh modified sequences.txt"


def test_slowest_step_identified():
    assert os.path.isfile(SLOWEST_STEP_FILE), f"File {SLOWEST_STEP_FILE} does not exist."
    with open(SLOWEST_STEP_FILE, "r") as f:
        content = f.read().strip()
    assert content == "step3_graph_build.sh", f"Expected 'step3_graph_build.sh' in {SLOWEST_STEP_FILE}, got '{content}'"


def test_graph_output_exists():
    assert os.path.isfile(GRAPH_OUTPUT_FILE), f"File {GRAPH_OUTPUT_FILE} does not exist. Did you run the orchestrator?"


def test_graph_output_correctness():
    assert os.path.isfile(FILTERED_SEQ_FILE), f"File {FILTERED_SEQ_FILE} does not exist."

    # Recompute the alignment filter from the canonical source dataset rather
    # than trusting the agent-controlled filtered_sequences.txt.
    source_sequences = canonical_sequences().splitlines()
    sequences = [sequence for sequence in source_sequences if "CG" in sequence]

    with open(FILTERED_SEQ_FILE, "r") as f:
        actual_filtered = [line.rstrip("\n") for line in f]
    assert actual_filtered == sequences, "filtered_sequences.txt is not the correct filter of sequences.txt"

    expected_edges = set()
    for s1 in sequences:
        for s2 in sequences:
            if s1 != s2 and s1[-4:] == s2[:4]:
                expected_edges.add(f"{s1} -> {s2}")

    actual_edges = set()
    with open(GRAPH_OUTPUT_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                actual_edges.add(line)

    missing = expected_edges - actual_edges
    extra = actual_edges - expected_edges

    assert not missing, f"Missing {len(missing)} expected edges in {GRAPH_OUTPUT_FILE}. Example: {list(missing)[0]}"
    assert not extra, f"Found {len(extra)} extra edges in {GRAPH_OUTPUT_FILE}. Example: {list(extra)[0]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
