#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR="$(mktemp -d)"
mkdir -p "$BACKUP_DIR/data"
cp -a /home/user/data/. "$BACKUP_DIR/data/"
if [ -e /home/user/results.tsv ]; then
    cp -a /home/user/results.tsv "$BACKUP_DIR/results.tsv"
    HAD_RESULTS=1
else
    HAD_RESULTS=0
fi

restore_state() {
    rm -rf /home/user/data
    mkdir -p /home/user/data
    cp -a "$BACKUP_DIR/data/." /home/user/data/
    if [ "$HAD_RESULTS" -eq 1 ]; then
        cp -a "$BACKUP_DIR/results.tsv" /home/user/results.tsv
    else
        rm -f /home/user/results.tsv
    fi
    rm -rf "$BACKUP_DIR"
}
trap restore_state EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import secrets
import shutil
import subprocess
import pytest

SCRIPT = pathlib.Path("/home/user/pipeline.sh")
RESULTS = pathlib.Path("/home/user/results.tsv")
DATA = pathlib.Path("/home/user/data")

ORIGINAL_EXPECTED = [
    "mol_A\t4\t1600\t80.1",
    "mol_C\t4\t1950\t95.5",
]


def assert_original_results():
    assert RESULTS.is_file(), f"Results file {RESULTS} is missing."
    with RESULTS.open("r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(ORIGINAL_EXPECTED), (
        f"Expected {len(ORIGINAL_EXPECTED)} lines in {RESULTS}, but found {len(lines)}."
    )

    for i, (expected, actual) in enumerate(zip(ORIGINAL_EXPECTED, lines)):
        expected_parts = expected.split("\t")
        actual_parts = actual.split("\t")
        assert len(actual_parts) == 4, f"Line {i+1} does not have exactly 4 tab-separated columns."
        assert actual_parts[0] == expected_parts[0], (
            f"Line {i+1} molecule name mismatch: expected {expected_parts[0]}, got {actual_parts[0]}."
        )
        assert actual_parts[1] == expected_parts[1], (
            f"Line {i+1} max degree mismatch: expected {expected_parts[1]}, got {actual_parts[1]}."
        )
        assert actual_parts[2] == expected_parts[2], (
            f"Line {i+1} peak frequency mismatch: expected {expected_parts[2]}, got {actual_parts[2]}."
        )
        try:
            actual_intensity = float(actual_parts[3])
            expected_intensity = float(expected_parts[3])
            assert abs(actual_intensity - expected_intensity) < 1e-6, (
                f"Line {i+1} peak intensity mismatch: expected {expected_intensity}, got {actual_intensity}."
            )
        except ValueError:
            pytest.fail(f"Line {i+1} peak intensity is not a valid float: {actual_parts[3]}")


def run_pipeline():
    if RESULTS.exists():
        RESULTS.unlink()
    completed = subprocess.run(
        ["bash", str(SCRIPT)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"pipeline.sh exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert RESULTS.is_file(), "pipeline.sh did not generate /home/user/results.tsv"


def test_pipeline_script_exists():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} is missing."


def test_results_tsv_content():
    assert_original_results()


def test_pipeline_is_nonempty_valid_shell():
    assert SCRIPT.stat().st_size > 0, "pipeline.sh is empty."
    completed = subprocess.run(
        ["bash", "-n", str(SCRIPT)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert completed.returncode == 0, f"pipeline.sh is not valid shell syntax: {completed.stderr}"


def test_pipeline_reproduces_original_results():
    run_pipeline()
    assert_original_results()


def test_pipeline_processes_unseen_graphs_and_spectra():
    token = secrets.token_hex(6)
    names = {
        "first": f"{token}_alpha",
        "low": f"{token}_beta",
        "second": f"{token}_delta",
        "high": f"{token}_gamma",
    }

    shutil.rmtree(DATA)
    graphs = DATA / "graphs"
    spectra = DATA / "spectra"
    graphs.mkdir(parents=True)
    spectra.mkdir(parents=True)

    # Two qualifying graphs, one maximum-degree-3 graph, and one maximum-degree-5 graph.
    graph_text = {
        names["first"]: "101 201\n101 202\n101 203\n101 204\n201 301\n",
        names["low"]: "1 2\n1 3\n1 4\n4 5\n",
        names["second"]: "7 8\n7 9\n7 10\n7 11\n9 12\n9 13\n",
        names["high"]: "50 51\n50 52\n50 53\n50 54\n50 55\n",
    }
    for name, text in graph_text.items():
        (graphs / f"{name}.edgelist").write_text(text)

    peak_frequency = str(secrets.randbelow(701) + 1200)
    peak_intensity = f"{secrets.randbelow(40000) / 1000 + 60:.3f}"
    nearby_intensity = f"{float(peak_intensity) - 1.125:.3f}"
    negative_peak = f"{-1 * (secrets.randbelow(5000) / 1000 + 1):.3f}"
    negative_lower = f"{float(negative_peak) - 4.5:.3f}"

    (spectra / f"{names['first']}.dat").write_text(
        f"999 999.0\n1000 {nearby_intensity}\n{peak_frequency} {peak_intensity}\n"
        f"2000 {nearby_intensity}\n2001 1000.0\n"
    )
    (spectra / f"{names['low']}.dat").write_text("1500 9999.0\n")
    (spectra / f"{names['second']}.dat").write_text(
        f"999 500.0\n1000 {negative_peak}\n1500 {negative_lower}\n"
        f"2000 {negative_lower}\n2001 600.0\n"
    )
    (spectra / f"{names['high']}.dat").write_text("1600 8888.0\n")

    run_pipeline()

    expected = [
        f"{names['first']}\t4\t{peak_frequency}\t{peak_intensity}",
        f"{names['second']}\t4\t1000\t{negative_peak}",
    ]
    actual = RESULTS.read_text().splitlines()
    assert actual == expected, f"Expected generated results {expected!r}, got {actual!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
