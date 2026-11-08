#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SOURCE = "/home/user/queuing_mcmc.go"
OBSERVATIONS = "/home/user/observations.csv"
PROFILE = "/home/user/cpu.prof"
RESULTS = "/home/user/results.txt"
BINARY = "/tmp/queuing_mcmc_verify"

EXPECTED_OBSERVATIONS = b"""lambda,x
1.0,0.435
2.0,0.697
3.0,0.893
4.0,1.052
5.0,1.187
6.0,1.305
7.0,1.411
8.0,1.506
9.0,1.701
10.0,1.621
"""


def strip_go_comments(text):
    out = []
    i = 0
    state = "code"
    quote = None
    while i < len(text):
        if state == "code":
            if text.startswith("//", i):
                state = "line"
                out.extend("  ")
                i += 2
            elif text.startswith("/*", i):
                state = "block"
                out.extend("  ")
                i += 2
            elif text[i] in ('"', "'", '`'):
                quote = text[i]
                state = "string"
                out.append(text[i])
                i += 1
            else:
                out.append(text[i])
                i += 1
        elif state == "line":
            if text[i] == "\n":
                out.append("\n")
                state = "code"
            else:
                out.append(" ")
            i += 1
        elif state == "block":
            if text.startswith("*/", i):
                out.extend("  ")
                i += 2
                state = "code"
            else:
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
        else:
            ch = text[i]
            out.append(ch)
            i += 1
            if quote != '`' and ch == "\\" and i < len(text):
                out.append(text[i])
                i += 1
            elif ch == quote:
                state = "code"
    return "".join(out)


def parse_results():
    assert os.path.isfile(RESULTS), f"The file {RESULTS} is missing."
    with open(RESULTS, "r", encoding="utf-8") as f:
        content = f.read().strip()
    parts = content.split(",")
    assert len(parts) == 2, f"Expected 2 comma-separated values in {RESULTS}, got {len(parts)}."
    try:
        mu = float(parts[0].strip())
        sigma = float(parts[1].strip())
    except ValueError:
        raise AssertionError(f"Could not parse values in {RESULTS} as floats. Content: {content}")
    assert math.isfinite(mu) and math.isfinite(sigma), "Results must be finite numbers."
    return mu, sigma


def validate_profile():
    assert os.path.isfile(PROFILE), f"The file {PROFILE} is missing."
    assert os.path.getsize(PROFILE) > 0, f"The file {PROFILE} is empty."
    assert os.path.getsize(PROFILE) > 100, "CPU profile is too small to be a real Go CPU profile."
    proc = subprocess.run(
        ["/usr/bin/go", "tool", "pprof", "-top", BINARY, PROFILE],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert proc.returncode == 0, f"cpu.prof is not a readable Go pprof profile:\n{proc.stdout}"
    assert "Total samples" in proc.stdout, f"pprof reported no CPU sample summary:\n{proc.stdout}"
    match = re.search(r"Total samples\s*=\s*([^\s]+)", proc.stdout)
    assert match and not re.fullmatch(r"0(?:\.0+)?(?:ns|us|ms|s)?", match.group(1)), \
        f"CPU profile contains no samples:\n{proc.stdout}"


def run_program():
    for path in (PROFILE, RESULTS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    proc = subprocess.run(
        [BINARY], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240
    )
    assert proc.returncode == 0, f"The compiled Go program failed:\n{proc.stdout}"
    mu, sigma = parse_results()
    validate_profile()
    return mu, sigma


def synthetic_dataset(mu_true=7.0):
    roots = [0.35 + 0.055 * i for i in range(24)]
    sensitivity = [-x / (3.0*x*x + mu_true) for x in roots]
    raw = [0.08 if i % 2 == 0 else -0.08 for i in range(len(roots))]
    projection = sum(a*b for a, b in zip(raw, sensitivity)) / sum(b*b for b in sensitivity)
    noise = [a - projection*b for a, b in zip(raw, sensitivity)]
    lines = ["lambda,x"]
    for root, err in zip(roots, noise):
        lam = root**3 + mu_true*root
        lines.append(f"{lam:.12f},{root + err:.12f}")
    return ("\n".join(lines) + "\n").encode()


def test_complete_mcmc_program():
    # Preserve the original existence assertion and ensure the supplied input was not replaced.
    assert os.path.isfile(SOURCE), f"The file {SOURCE} is missing."
    with open(OBSERVATIONS, "rb") as f:
        original_data = f.read()
    assert original_data == EXPECTED_OBSERVATIONS, "observations.csv was modified."

    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()
    code = strip_go_comments(source).replace("_", "")

    # Verify that the submitted artifact contains the required Go mechanisms, rather than
    # merely emitting precomputed files.
    required_patterns = {
        "runtime/pprof import": r'"runtime/pprof"',
        "CPU profiling start": r'pprof\s*\.\s*StartCPUProfile\s*\(',
        "CPU profiling stop": r'pprof\s*\.\s*StopCPUProfile\s*\(',
        "sync package": r'"sync"',
        "WaitGroup": r'\bWaitGroup\b',
        "WaitGroup Add": r'\.\s*Add\s*\(',
        "WaitGroup Done": r'\.\s*Done\s*\(',
        "WaitGroup Wait": r'\.\s*Wait\s*\(',
        "goroutine": r'\bgo\s+',
        "CSV reader": r'"encoding/csv"',
        "normal proposals": r'\.\s*NormFloat64\s*\(',
        "15,000 iterations": r'\b15000\b',
        "5,000 burn-in": r'\b5000\b',
        "proposal scale 0.1": r'(?<![\w.])(?:0?\.1|1e-1)(?![\w.])',
        "proposal scale 0.05": r'(?<![\w.])(?:0?\.05|5e-2)(?![\w.])',
        "lower sigma prior": r'(?<![\w.])(?:0?\.01|1e-2)(?![\w.])',
        "Newton tolerance": r'(?<![\w.])(?:0?\.000001|1e-6)(?![\w.])',
        "Newton iteration limit": r'\b100\b',
    }
    for description, pattern in required_patterns.items():
        assert re.search(pattern, code, re.IGNORECASE), f"Go source is missing required mechanism: {description}."
    assert re.search(r'(?<![\w.])4(?![\w.])', code), "Go source does not specify four chains."

    build = subprocess.run(
        ["/usr/bin/go", "build", "-o", BINARY, SOURCE],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120
    )
    assert build.returncode == 0, f"Go source does not compile:\n{build.stdout}"

    # Exercise the program on verifier-generated observations whose posterior is far from
    # the supplied dataset. This rejects hard-coded result/profile writers.
    try:
        with open(OBSERVATIONS, "wb") as f:
            f.write(synthetic_dataset())
        synthetic_mu, synthetic_sigma = run_program()
        assert 6.4 <= synthetic_mu <= 7.6, \
            f"On generated data, estimated mu ({synthetic_mu}) is not near the generating value 7.0."
        assert 0.035 <= synthetic_sigma <= 0.25, \
            f"On generated data, estimated sigma ({synthetic_sigma}) is implausible."
    finally:
        with open(OBSERVATIONS, "wb") as f:
            f.write(original_data)

    # Run again on the actual task input, leaving the demanded artifacts in place and
    # retaining the original verifier's numerical assertions.
    mu, sigma = run_program()
    assert 2.0 <= mu <= 3.5, f"Estimated mu ({mu}) is outside the expected range [2.0, 3.5]."
    assert 0.05 <= sigma <= 0.4, f"Estimated sigma ({sigma}) is outside the expected range [0.05, 0.4]."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
