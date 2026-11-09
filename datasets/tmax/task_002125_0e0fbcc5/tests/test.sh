#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess

PROJECT = "/home/user/perf_app"
RESULTS = "/home/user/profile_results.txt"
BINARY = os.path.join(PROJECT, "metrics_calc")


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=30, **kwargs)


def check_results():
    assert os.path.exists(RESULTS), f"The expected output file {RESULTS} was not generated."
    assert os.path.isfile(RESULTS), f"{RESULTS} is not a valid file."

    with open(RESULTS, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == 10, f"Expected exactly 10 lines in {RESULTS}, but found {len(lines)}."
    for i in range(10):
        expected_val = int(math.sqrt(i * 100))
        expected_line = f"Result {i}: {expected_val}"
        assert lines[i] == expected_line, (
            f"Line {i+1} mismatch. Expected: '{expected_line}', but got: '{lines[i]}'."
        )


def main():
    build_path = os.path.join(PROJECT, "build.sh")
    compute_path = os.path.join(PROJECT, "compute.c")
    assert os.path.isfile(build_path), "build.sh is missing"
    assert os.access(build_path, os.X_OK), "build.sh is not executable"

    build_text = open(build_path).read()
    assert re.search(r"(?:^|\s)(?:gcc|cc)(?:\s|$)", build_text), "build.sh does not invoke a C compiler"
    assert "main.c" in build_text and "compute.c" in build_text, "build.sh does not compile both source files"
    assert re.search(r"(?:^|\s)-lm(?:\s|$)", build_text), "build.sh does not link the math library"

    roots = run(["git", "rev-list", "--max-parents=0", "HEAD"], cwd=PROJECT)
    assert roots.returncode == 0, roots.stderr
    root_commits = roots.stdout.strip().splitlines()
    assert len(root_commits) == 1, "Could not identify the original repository commit"
    historical = run(["git", "show", f"{root_commits[0]}:compute.c"], cwd=PROJECT)
    assert historical.returncode == 0, historical.stderr
    match = re.search(r'legacy_key\s*=\s*"([^"\\]+)"', historical.stdout)
    assert match, "The legacy key is not recoverable from the original git history"
    legacy_key = match.group(1)

    compute_text = open(compute_path).read()
    assert legacy_key not in compute_text, "The removed legacy key is still present literally in current compute.c"
    assert not re.search(r"int\s*\*\s*results\s*=\s*NULL", compute_text), "The NULL results allocation bug remains"
    assert re.search(r"results\s*=\s*(?:malloc|calloc)\s*\(", compute_text), "results is not dynamically allocated"

    for path in (BINARY, RESULTS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    built = run(["bash", "./build.sh"], cwd=PROJECT)
    assert built.returncode == 0, f"build.sh failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(BINARY), "build.sh did not create metrics_calc"
    assert os.access(BINARY, os.X_OK), "metrics_calc is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "metrics_calc is not a compiled ELF executable"

    invalid = run([BINARY, legacy_key + "_invalid"], cwd=PROJECT)
    assert invalid.returncode != 0, "metrics_calc accepted an invalid API key"
    assert not os.path.exists(RESULTS), "An invalid API key generated the profiling report"

    valid = run([BINARY, legacy_key], cwd=PROJECT)
    assert valid.returncode == 0, f"Built application failed:\n{valid.stdout}\n{valid.stderr}"
    check_results()

    verified_binary = "/tmp/metrics_calc_verified"
    compiled = run([
        "gcc", "-g", "-O0", "-fsanitize=address",
        os.path.join(PROJECT, "main.c"), compute_path,
        "-o", verified_binary, "-lm"
    ])
    assert compiled.returncode == 0, f"Current C sources do not compile:\n{compiled.stdout}\n{compiled.stderr}"

    os.remove(RESULTS)
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0"
    checked = run([verified_binary, legacy_key], cwd=PROJECT, env=env)
    assert checked.returncode == 0, (
        f"Application compiled from the submitted sources failed memory-safe execution:\n"
        f"{checked.stdout}\n{checked.stderr}"
    )
    check_results()


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
