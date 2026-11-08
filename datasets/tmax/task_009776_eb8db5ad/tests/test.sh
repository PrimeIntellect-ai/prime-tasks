#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import time


def run(cmd, **kwargs):
    kwargs.setdefault("check", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("capture_output", True)
    return subprocess.run(cmd, **kwargs)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def test_complete_task():
    # Preserve and strengthen the original FASTA assertions.
    fasta_path = "/home/user/primers.fasta"
    assert os.path.isfile(fasta_path), f"File {fasta_path} does not exist. Did you run the sequence generator?"
    with open(fasta_path, "r") as f:
        lines = f.readlines()
    assert len(lines) == 20000, f"Expected 20000 lines in {fasta_path}, but found {len(lines)}."
    assert lines[0].startswith(">primer_0"), "First sequence header is incorrect."

    seqgen_path = "/home/user/seqgen/seqgen"
    assert os.path.isfile(seqgen_path), "The seqgen executable was not built."
    assert os.access(seqgen_path, os.X_OK), "The seqgen executable is not executable."

    # Independently compile the supplied deterministic generator and compare every byte.
    generator_source = r'''#include <stdio.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    srand(42);
    const char bases[] = "ACGT";
    for (int i = 0; i < n; i++) {
        printf(">primer_%d\n", i);
        for (int j = 0; j < 20; j++) putchar(bases[rand() % 4]);
        putchar('\n');
    }
    return 0;
}
'''
    with tempfile.TemporaryDirectory() as td:
        expected_c = os.path.join(td, "expected.c")
        expected_bin = os.path.join(td, "expected_seqgen")
        expected_fasta = os.path.join(td, "expected.fasta")
        with open(expected_c, "w") as f:
            f.write(generator_source)
        run(["gcc", "-O2", "-o", expected_bin, expected_c])
        with open(expected_fasta, "wb") as out:
            subprocess.run([expected_bin, "10000"], check=True, stdout=out, timeout=60)
        assert sha256(fasta_path) == sha256(expected_fasta), \
            "primers.fasta is not the deterministic output of the supplied generator."

    # Preserve the original requirement that the agent produced a nonempty profile.
    prof_path = "/home/user/cpu.prof"
    assert os.path.isfile(prof_path), f"File {prof_path} does not exist. Did you add pprof profiling and run the Go app?"
    assert os.path.getsize(prof_path) > 0, f"File {prof_path} is empty."

    # Preserve the report assertions before independently exercising the implementation.
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."
    with open(report_path, "r") as f:
        report = json.load(f)
    assert "integral_value" in report, "Key 'integral_value' missing from report.json."
    assert "bottleneck_function" in report, "Key 'bottleneck_function' missing from report.json."
    assert set(report) == {"integral_value", "bottleneck_function"}, \
        "report.json must contain exactly the specified keys."
    integral_value = report["integral_value"]
    assert isinstance(integral_value, (int, float)) and not isinstance(integral_value, bool), \
        "integral_value must be a number."
    assert math.isclose(integral_value, 1.0, abs_tol=0.001), \
        f"integral_value is {integral_value}, expected ~1.0000."
    assert report["bottleneck_function"] == "main.slowAlignmentScoring", \
        f"bottleneck_function is '{report['bottleneck_function']}', expected 'main.slowAlignmentScoring'."

    analyzer_dir = "/home/user/analyzer"
    main_go = os.path.join(analyzer_dir, "main.go")
    analyzer_artifact = os.path.join(analyzer_dir, "analyzer")
    assert os.path.isfile(main_go), "main.go is missing."
    assert os.path.isfile(analyzer_artifact), "The analyzer executable was not built."
    assert os.access(analyzer_artifact, os.X_OK), "The analyzer executable is not executable."

    # Copy the submitted Go implementation into isolation, then directly test Simpson's rule.
    with tempfile.TemporaryDirectory() as td:
        go_files = [name for name in os.listdir(analyzer_dir)
                    if name.endswith(".go") and not name.endswith("_test.go")]
        assert "main.go" in go_files
        for name in go_files:
            shutil.copy2(os.path.join(analyzer_dir, name), os.path.join(td, name))

        simpson_test = r'''package main
import (
    "math"
    "testing"
)
func TestVerifierSimpsonIntegration(t *testing.T) {
    x1 := []float64{0, 0.5, 1}
    y1 := []float64{0, 0.25, 1}
    if got := SimpsonIntegration(x1, y1); math.Abs(got-1.0/3.0) > 1e-12 {
        t.Fatalf("quadratic integral: got %.15g, want %.15g", got, 1.0/3.0)
    }
    x2 := []float64{0, 0.5, 1, 1.5, 2, 2.5, 3}
    y2 := []float64{1, 4, 2, 8, 3, 7, 5}
    want := 92.0 / 6.0
    if got := SimpsonIntegration(x2, y2); math.Abs(got-want) > 1e-12 {
        t.Fatalf("weighted samples: got %.15g, want %.15g", got, want)
    }
}
'''
        with open(os.path.join(td, "verifier_simpson_test.go"), "w") as f:
            f.write(simpson_test)

        env = os.environ.copy()
        env["GO111MODULE"] = "off"
        tested = run(["go", "test", "."], cwd=td, env=env, timeout=120)
        assert tested.returncode == 0

        verified_bin = os.path.join(td, "analyzer_verified")
        run(["go", "build", "-o", verified_bin, "."], cwd=td, env=env, timeout=120)

        # Remove the self-reported profile and require the submitted source to create a
        # fresh, parseable CPU profile while processing the exact full dataset.
        os.unlink(prof_path)
        started = time.time()
        executed = run([verified_bin, fasta_path], cwd=td, env=env, timeout=300)
        assert os.path.isfile(prof_path), "Running the submitted analyzer did not create /home/user/cpu.prof."
        assert os.path.getsize(prof_path) > 0, "The freshly generated CPU profile is empty."
        assert os.path.getmtime(prof_path) >= started - 1, "The CPU profile was not freshly generated."

        match = re.search(r"Integrated Area:\s*([-+0-9.eE]+)", executed.stdout)
        assert match, f"Analyzer output did not contain an integrated area: {executed.stdout!r}"
        actual_integral = float(match.group(1))

        # Independently calculate the expected Simpson result for the application's PDF.
        n = 1001
        min_x, max_x = -5.0, 5.0
        step = (max_x - min_x) / (n - 1)
        ys = [(1.0 / math.sqrt(2.0 * math.pi)) *
              math.exp(-0.5 * (min_x + i * step) ** 2) for i in range(n)]
        expected_integral = (step / 3.0) * (
            ys[0] + ys[-1] +
            4.0 * sum(ys[i] for i in range(1, n - 1, 2)) +
            2.0 * sum(ys[i] for i in range(2, n - 1, 2)))
        assert math.isclose(actual_integral, expected_integral, abs_tol=1e-6), \
            f"Analyzer printed {actual_integral}, expected {expected_integral}."
        assert report["integral_value"] == round(actual_integral, 4), \
            "report.json integral_value does not equal the analyzer result rounded to 4 places."

        # Parse the fresh profile with the Go tool and derive the hottest cumulative
        # non-wrapper function in package main instead of trusting report.json.
        pprof = run(["go", "tool", "pprof", "-top", "-cum", "-nodecount=100",
                     verified_bin, prof_path], timeout=120)
        profile_text = pprof.stdout + "\n" + pprof.stderr
        assert "main.slowAlignmentScoring" in profile_text, \
            "The CPU profile has no samples attributed to main.slowAlignmentScoring."

        ranked_main = []
        for line in pprof.stdout.splitlines():
            m = re.search(r"\s(main\.[^\s]+)\s*$", line)
            if m and m.group(1) != "main.main" and m.group(1) not in ranked_main:
                ranked_main.append(m.group(1))
        assert ranked_main, "Could not derive package-main functions from the CPU profile."
        derived_bottleneck = ranked_main[0]
        assert derived_bottleneck == "main.slowAlignmentScoring", \
            f"Profile identified {derived_bottleneck} as the bottleneck, not main.slowAlignmentScoring."
        assert report["bottleneck_function"] == derived_bottleneck, \
            "report.json bottleneck_function does not match the freshly parsed CPU profile."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
