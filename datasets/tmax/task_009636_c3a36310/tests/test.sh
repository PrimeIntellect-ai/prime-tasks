#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
from decimal import Decimal

import pytest

TEST_SCRIPT = "/home/user/test_sim.sh"
FIX_SCRIPT = "/home/user/fix_sim.sh"
SOURCE = "/home/user/sim/network_mc.c"
EXECUTABLE = "/home/user/sim/simulate"
STATS = "/home/user/sim_stats.txt"
STABLE = "/home/user/stable_score.txt"


def assert_bash_without_python(path):
    data = open(path, "r", encoding="utf-8").read()
    first = data.splitlines()[0] if data.splitlines() else ""
    assert re.match(r"^#!.*\bbash\b", first), f"{path} is not a Bash script."

    command_text = "\n".join(line.split("#", 1)[0] for line in data.splitlines()[1:])
    python_command = re.compile(
        r"(?:^|[\s;&|()])(?:/[^\s;&|()]*/)?python(?:[0-9.]+)?(?=$|[\s;&|()])",
        re.MULTILINE | re.IGNORECASE,
    )
    assert not python_command.search(command_text), f"{path} must not invoke Python."


def run_script(path, log_path, threads):
    env = os.environ.copy()
    env["VERIFIER_RUN_LOG"] = log_path
    env["OMP_NUM_THREADS"] = str(threads)
    env["OMP_DYNAMIC"] = "FALSE"
    result = subprocess.run(
        [path], cwd="/home/user", env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240,
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_run_log(path):
    assert os.path.isfile(path), "The simulation executable did not record any runs."
    lines = open(path, "r", encoding="utf-8").read().splitlines()
    parsed = []
    for line in lines:
        match = re.fullmatch(r"([0-9]+) ([0-9]+\.[0-9]+)", line)
        assert match, f"Malformed verifier run record: {line!r}"
        parsed.append((int(match.group(1)), match.group(2)))
    return parsed


def test_scripts_execute_and_produce_real_results():
    # Preserve the original existence and owner-executable assertions.
    for path in (TEST_SCRIPT, FIX_SCRIPT):
        assert os.path.isfile(path), f"Script {path} does not exist."
        st = os.stat(path)
        assert bool(st.st_mode & stat.S_IXUSR), f"Script {path} is not executable."
        assert_bash_without_python(path)

    original_source = open(SOURCE, "rb").read()
    source_text = original_source.decode("utf-8")
    marker = '    printf("Final Score: %.6f\\n", total_score);'
    assert marker in source_text, "Unexpected simulation source layout."

    instrumentation = '''    char *verifier_log = getenv("VERIFIER_RUN_LOG");
    if (verifier_log) {
        FILE *vf = fopen(verifier_log, "a");
        if (vf) {
            fprintf(vf, "%d %.6f\\n", omp_get_max_threads(), total_score);
            fclose(vf);
        }
    }
'''
    instrumented = source_text.replace(marker, instrumentation + marker, 1).encode("utf-8")

    try:
        with open(SOURCE, "wb") as f:
            f.write(instrumented)

        for path in (EXECUTABLE, STATS, STABLE, "/tmp/test_sim_runs.log", "/tmp/fix_sim_runs.log"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        # Execute Step 1 from a clean state. The instrumented source records every
        # real execution and its actual printed score without changing the score.
        run_script(TEST_SCRIPT, "/tmp/test_sim_runs.log", 4)
        assert open(SOURCE, "rb").read() == instrumented, "test_sim.sh modified network_mc.c."
        assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} was not created."
        assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."

        linked = subprocess.run(
            ["ldd", EXECUTABLE], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, check=True,
        ).stdout
        assert "libgomp" in linked, "The simulation was not compiled with OpenMP (-fopenmp)."
        assert "libm.so" in linked, "The simulation was not linked with the math library (-lm)."

        runs = read_run_log("/tmp/test_sim_runs.log")
        assert len(runs) == 100, f"test_sim.sh must run the simulation 100 times; observed {len(runs)} runs."
        assert all(t > 1 for t, _ in runs), "Step 1 did not exercise the multi-threaded OpenMP simulation."
        scores = [score for _, score in runs]
        expected_unique = len(set(scores))
        expected_min = min(scores, key=Decimal)
        expected_max = max(scores, key=Decimal)

        # Preserve the original output assertions, then compare against the values
        # independently captured from the 100 executions.
        assert os.path.isfile(STATS), f"Output file {STATS} does not exist. Did you run test_sim.sh?"
        content = open(STATS, "r", encoding="utf-8").read().strip()
        old_pattern = r"^Unique:\s*([0-9]+),\s*Min:\s*([0-9\.]+),\s*Max:\s*([0-9\.]+)$"
        old_match = re.match(old_pattern, content)
        assert old_match is not None, (
            f"File {STATS} content {content!r} does not match the expected format "
            "'Unique: <N>, Min: <val>, Max: <val>'."
        )
        assert int(old_match.group(1)) > 1, (
            f"Expected non-deterministic output with Unique > 1, but got {old_match.group(1)}."
        )
        exact = re.fullmatch(r"Unique: ([0-9]+), Min: ([0-9\.]+), Max: ([0-9\.]+)", content)
        assert exact, f"{STATS} is not in the exact required format."
        assert int(exact.group(1)) == expected_unique, "Unique count does not match the 100 actual runs."
        assert exact.group(2) == expected_min, "Minimum does not match the 100 actual runs."
        assert exact.group(3) == expected_max, "Maximum does not match the 100 actual runs."

        # Execute Step 2 against the compiled simulation and verify both the run
        # count and the OpenMP configuration observed inside every process.
        run_script(FIX_SCRIPT, "/tmp/fix_sim_runs.log", 4)
        assert open(SOURCE, "rb").read() == instrumented, "fix_sim.sh modified network_mc.c."
        stable_runs = read_run_log("/tmp/fix_sim_runs.log")
        assert len(stable_runs) == 10, f"fix_sim.sh must run the simulation 10 times; observed {len(stable_runs)} runs."
        assert all(t == 1 for t, _ in stable_runs), "fix_sim.sh did not force single-threaded OpenMP execution."
        stable_scores = [score for _, score in stable_runs]
        assert len(set(stable_scores)) == 1, "The 10 runs performed by fix_sim.sh were not stable."

        # Preserve the original stable-score format assertion and verify that the
        # value came from the final real execution.
        assert os.path.isfile(STABLE), f"Output file {STABLE} does not exist. Did you run fix_sim.sh?"
        stable_content = open(STABLE, "r", encoding="utf-8").read().strip()
        old_stable_pattern = r"^Stable Score:\s*([0-9\.]+)$"
        old_stable_match = re.match(old_stable_pattern, stable_content)
        assert old_stable_match is not None, (
            f"File {STABLE} content {stable_content!r} does not match the expected format "
            "'Stable Score: <val>'."
        )
        exact_stable = re.fullmatch(r"Stable Score: ([0-9\.]+)", stable_content)
        assert exact_stable, f"{STABLE} is not in the exact required format."
        assert exact_stable.group(1) == stable_scores[-1], (
            "stable_score.txt does not contain the score from the final simulation run."
        )
    finally:
        with open(SOURCE, "wb") as f:
            f.write(original_source)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
