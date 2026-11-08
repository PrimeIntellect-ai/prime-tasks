#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import tempfile
import uuid

DETECTOR = "/home/user/detector"
SOURCE = "/home/user/detector.c"
NOTEBOOK = "/home/user/pipeline.ipynb"
LIBDIR = "/app/vendored/seq-mcmc-1.0"


def run_detector(path, env=None, executable=DETECTOR):
    return subprocess.run([executable, path], capture_output=True, env=env, timeout=15)


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR), f"Detector executable not found at {DETECTOR}"
    st = os.stat(DETECTOR)
    assert bool(st.st_mode & stat.S_IXUSR), f"Detector at {DETECTOR} is not executable"


def test_detector_uses_openmp():
    assert os.path.isfile(DETECTOR), f"Detector executable not found at {DETECTOR}"
    result = subprocess.run(["ldd", DETECTOR], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run ldd on detector"
    assert "libgomp" in result.stdout, "Detector is not dynamically linked to libgomp (OpenMP not properly enabled)"


def test_makefile_fixed_and_library_builds():
    makefile_path = os.path.join(LIBDIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-fomp" not in content, "The deliberate typo '-fomp' is still present in the Makefile"
    assert "-fopenmp" in content, "The correct '-fopenmp' flag was not found in the Makefile"

    result = subprocess.run(["make", "clean", "all"], cwd=LIBDIR, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"Fixed vendored library does not build:\n{result.stdout}\n{result.stderr}"
    artifacts = [os.path.join(LIBDIR, "mcmc_score.o"), os.path.join(LIBDIR, "libseq-mcmc.a")]
    artifacts = [p for p in artifacts if os.path.isfile(p)]
    assert artifacts, "Library build produced neither mcmc_score.o nor libseq-mcmc.a"
    nm = subprocess.run(["nm", "-g"] + artifacts, capture_output=True, text=True)
    assert nm.returncode == 0 and "compute_artifact_posterior" in nm.stdout, \
        "Built library artifact does not export compute_artifact_posterior"


def test_detector_source_present_and_uses_required_api_and_openmp():
    assert os.path.isfile(SOURCE), f"Detector source not found at {SOURCE}"
    with open(SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bcompute_artifact_posterior\s*\(", source), \
        "detector.c does not call compute_artifact_posterior"
    assert re.search(r"#\s*pragma\s+omp\s+parallel", source), \
        "detector.c does not contain an OpenMP parallel construct"


def test_notebook_has_successful_openmp_build_cell():
    assert os.path.isfile(NOTEBOOK), f"Notebook not found at {NOTEBOOK}"
    with open(NOTEBOOK, "r", encoding="utf-8") as f:
        notebook = json.load(f)
    candidates = []
    for cell in notebook.get("cells", []):
        if cell.get("cell_type") != "code":
            continue
        text = "".join(cell.get("source", []))
        if re.match(r"\s*%%bash(?:\s|$)", text) and "detector.c" in text and "-fopenmp" in text:
            candidates.append(re.sub(r"^\s*%%bash[^\n]*\n?", "", text, count=1))
    assert candidates, "pipeline.ipynb lacks a bash cell compiling detector.c with -fopenmp"
    errors = []
    for script in candidates:
        result = subprocess.run(["bash", "-e", "-c", script], cwd="/home/user", capture_output=True,
                                text=True, timeout=60)
        if result.returncode == 0 and os.path.isfile(DETECTOR) and os.access(DETECTOR, os.X_OK):
            return
        errors.append(result.stdout + result.stderr)
    assert False, "Notebook OpenMP compilation cell failed:\n" + "\n".join(errors)


def test_source_build_calls_posterior_and_parallelizes_sequence_scoring():
    bad = "BAD_" + uuid.uuid4().hex
    edge = "EDGE_" + uuid.uuid4().hex
    overlap = os.path.join(tempfile.gettempdir(), "overlap_" + uuid.uuid4().hex)
    stub = r'''
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
static volatile int active = 0;
double compute_artifact_posterior(const char *seq) {
    int n = __sync_add_and_fetch(&active, 1);
    const char *overlap = getenv("POSTERIOR_OVERLAP_FILE");
    if (n > 1 && overlap) {
        int fd = open(overlap, O_WRONLY | O_CREAT, 0600);
        if (fd >= 0) close(fd);
    }
    usleep(30000);
    double result = 0.1;
    const char *bad = getenv("POSTERIOR_BAD_SEQUENCE");
    const char *edge = getenv("POSTERIOR_EDGE_SEQUENCE");
    if (bad && strcmp(seq, bad) == 0) result = 0.91;
    else if (edge && strcmp(seq, edge) == 0) result = 0.80;
    __sync_sub_and_fetch(&active, 1);
    return result;
}
'''
    with tempfile.TemporaryDirectory(prefix="detector-source-test-") as td:
        stub_path = os.path.join(td, "posterior_stub.c")
        rebuilt = os.path.join(td, "detector")
        with open(stub_path, "w") as f:
            f.write(stub)
        build = subprocess.run([
            "gcc", "-O0", "-fopenmp", "-I", LIBDIR, SOURCE, stub_path, "-o", rebuilt
        ], capture_output=True, text=True, timeout=30)
        assert build.returncode == 0, f"detector.c cannot be compiled against the seq-mcmc API:\n{build.stderr}"

        env = os.environ.copy()
        env.update({
            "OMP_NUM_THREADS": "4",
            "OMP_DYNAMIC": "FALSE",
            "POSTERIOR_BAD_SEQUENCE": bad,
            "POSTERIOR_EDGE_SEQUENCE": edge,
            "POSTERIOR_OVERLAP_FILE": overlap,
        })
        clean_path = os.path.join(td, uuid.uuid4().hex + ".fa")
        bad_path = os.path.join(td, uuid.uuid4().hex + ".data")
        with open(clean_path, "w") as f:
            f.write(">edge\n" + edge[:len(edge)//2] + "\n" + edge[len(edge)//2:] + "\n")
            for i in range(64):
                f.write(f">clean_{i}\nACGT{i}TGCA\n")
        with open(bad_path, "w") as f:
            f.write(">first\nACGT\n>target\n" + bad[:7] + "\n" + bad[7:] + "\n>last\nTGCA\n")

        assert run_detector(clean_path, env, rebuilt).returncode == 0, \
            "A posterior exactly equal to 0.80 must remain clean"
        assert os.path.exists(overlap), \
            "Scoring calls did not overlap; detector.c is not parallelizing multiple sequences"
        assert run_detector(bad_path, env, rebuilt).returncode == 1, \
            "Source-built detector did not reject a sequence whose library posterior exceeded 0.80"


def test_detector_dynamic_content_on_unpredictable_paths():
    with tempfile.TemporaryDirectory(prefix="fasta-adversarial-") as td:
        clean = os.path.join(td, uuid.uuid4().hex)
        evil_split = os.path.join(td, uuid.uuid4().hex + ".txt")
        evil_last = os.path.join(td, uuid.uuid4().hex + ".fa")
        with open(clean, "w") as f:
            f.write(">EVIL_only_in_header\nACGTACGT\n>second\nTGCATGCA\n")
        with open(evil_split, "w") as f:
            f.write(">one\nACGT\n>two\nTGCAEVI\nLGCA\n")
        with open(evil_last, "w") as f:
            f.write(">one\nACGT\n>two\nTGCA\n>three\nXXEVILXX\n")
        assert run_detector(clean).returncode == 0, "Detector treated header text as sequence contamination"
        assert run_detector(evil_split).returncode == 1, "Detector failed to parse a multiline contaminated sequence"
        assert run_detector(evil_last).returncode == 1, "Detector failed to score all sequences in a FASTA file"


def test_exactly_one_argument_required():
    no_arg = subprocess.run([DETECTOR], capture_output=True, timeout=10)
    two_args = subprocess.run([DETECTOR, "/dev/null", "/dev/null"], capture_output=True, timeout=10)
    assert no_arg.returncode not in (0, 1), "Detector accepted zero FASTA arguments"
    assert two_args.returncode not in (0, 1), "Detector accepted more than one FASTA argument"


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    failed_clean = [os.path.basename(p) for p in clean_files if run_detector(p).returncode != 0]
    failed_evil = [os.path.basename(p) for p in evil_files if run_detector(p).returncode != 1]
    error_msgs = []
    if failed_clean:
        error_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean files modified/rejected (expected exit code 0): {', '.join(failed_clean)}")
    if failed_evil:
        error_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed (expected exit code 1): {', '.join(failed_evil)}")
    assert not error_msgs, " | ".join(error_msgs)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
