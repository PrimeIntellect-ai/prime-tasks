#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

ORIGINAL=/app/stellar_core_sim.verifier-original
SIM=/app/stellar_core_sim
restore_sim() {
    if [ -e "$ORIGINAL" ]; then
        rm -f "$SIM"
        mv "$ORIGINAL" "$SIM"
    fi
}
trap restore_sim EXIT

if [ ! -f "$SIM" ] || [ ! -x "$SIM" ]; then
    exit 0
fi
mv "$SIM" "$ORIGINAL" || exit 0

cat > /tmp/stellar_core_sim_wrapper.c <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc != 2) return 1;
    char *end = NULL;
    double r = strtod(argv[1], &end);
    if (end == argv[1] || *end != '\0' || !isfinite(r)) return 1;

    int idx = (int)lround(r * 10.0) - 1;
    int state = open("/tmp/core_call_state.bin", O_RDWR | O_CREAT, 0600);
    if (state < 0) return 2;
    if (flock(state, LOCK_EX) != 0) return 2;

    struct stat st;
    if (fstat(state, &st) != 0) return 2;
    if (st.st_size < (off_t)(100 * sizeof(int))) {
        if (ftruncate(state, 100 * sizeof(int)) != 0) return 2;
    }

    int count = 0;
    if (idx >= 0 && idx < 100 && fabs(r - (idx + 1) / 10.0) < 1e-7) {
        if (pread(state, &count, sizeof(count), idx * sizeof(int)) != sizeof(count)) return 2;
        int next = count + 1;
        if (pwrite(state, &next, sizeof(next), idx * sizeof(int)) != sizeof(next)) return 2;
    }

    int logfd = open("/tmp/core_calls.log", O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (logfd < 0) return 2;
    dprintf(logfd, "%.17g %d\n", r, count);
    close(logfd);
    flock(state, LOCK_UN);
    close(state);

    int j = (count * 37) % 50;
    if (j < 0) j += 50;
    double noise = ((double)j - 24.5) * sqrt(12.0) * 5.0 / 50.0;
    double density = 50.0 * exp(-0.5 * r) + noise;
    printf("Density: %.12f\n", density);
    return 0;
}
EOF

if ! gcc -O2 -o "$SIM" /tmp/stellar_core_sim_wrapper.c -lm; then
    exit 0
fi
chmod 755 "$SIM"
rm -f /tmp/core_call_state.bin /tmp/core_calls.log

cat > /tmp/test_final_state.py <<'PYEOF'
import math
import os
import re
import subprocess
from collections import Counter

import pytest

SCRIPT = "/home/user/analyze_core.sh"
LOG = "/tmp/core_calls.log"


def test_analyze_core_script_exists():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_shell_implementation_and_bootstrap_evidence():
    with open(SCRIPT, "r", errors="replace") as f:
        source = f.read()
    first = source.splitlines()[0] if source.splitlines() else ""
    assert re.search(r"^#!.*\b(?:ba)?sh\b", first), "analyze_core.sh must be a Bash/POSIX shell script"
    assert not re.search(r"(^|[^A-Za-z0-9_])(python3?|Rscript|gcc|clang)([^A-Za-z0-9_]|$)", source), \
        "Core logic may not be delegated to Python, R, or C"
    assert any(int(n) >= 500 for n in re.findall(r"\b\d+\b", source)), \
        "No bootstrap iteration count of at least 500 was found"
    assert re.search(r"rand\s*\(|\$RANDOM|\bshuf\b|/dev/urandom", source), \
        "No random resampling mechanism was found"


def test_analyze_core_output_collection_and_metrics():
    try:
        result = subprocess.run(
            [SCRIPT], capture_output=True, text=True, timeout=240, check=True
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Execution of {SCRIPT} timed out")
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Execution of {SCRIPT} failed with return code {e.returncode}.\n"
            f"Stdout: {e.stdout}\nStderr: {e.stderr}"
        )

    number = r"([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)"
    match = re.fullmatch(
        rf"MEAN_MASS:\s*{number}\s*\n"
        rf"CI_LOWER:\s*{number}\s*\n"
        rf"CI_UPPER:\s*{number}\s*\n?",
        result.stdout,
    )
    assert match is not None, f"Output must contain exactly the required three lines:\n{result.stdout}"
    mass, ci_lower, ci_upper = map(float, match.groups())
    assert all(math.isfinite(x) for x in (mass, ci_lower, ci_upper))
    assert ci_lower < mass < ci_upper, "Confidence interval must contain the reported mean"

    assert os.path.exists(LOG), "The simulation binary was not queried"
    calls = []
    with open(LOG) as f:
        for line in f:
            fields = line.split()
            assert len(fields) == 2, f"Malformed simulator call log entry: {line!r}"
            calls.append((float(fields[0]), int(fields[1])))

    assert len(calls) == 5000, f"Expected exactly 5000 simulator queries, observed {len(calls)}"
    radius_counts = Counter()
    per_radius_indices = {}
    for radius, index in calls:
        tenth = round(radius * 10)
        assert 1 <= tenth <= 100 and abs(radius - tenth / 10.0) < 1e-7, \
            f"Invalid sampled radius: {radius}"
        radius_counts[tenth] += 1
        per_radius_indices.setdefault(tenth, []).append(index)

    assert set(radius_counts) == set(range(1, 101)), "All radii from 0.1 through 10.0 must be sampled"
    assert all(radius_counts[i] == 50 for i in range(1, 101)), \
        "Each radius must be queried exactly 50 times"
    assert all(sorted(per_radius_indices[i]) == list(range(50)) for i in range(1, 101)), \
        "Each radius must have 50 distinct simulator observations"

    # The instructed trapezoidal rule over the sampled grid, using the exact
    # expectation of the supplied density model.
    true_mass = 0.0
    weights = []
    for i in range(1, 101):
        r = i / 10.0
        trap_width = 0.05 if i in (1, 100) else 0.1
        weight = trap_width * 4.0 * math.pi * r * r
        weights.append(weight)
        true_mass += weight * 50.0 * math.exp(-0.5 * r)

    error = abs(mass - true_mass) / true_mass
    assert error <= 0.05, \
        f"MEAN_MASS {mass} deviates more than 5% from truth {true_mass}. Error: {error:.4f}"
    assert abs(mass - true_mass) <= max(15.0, 0.01 * true_mass), \
        f"MEAN_MASS {mass} is inconsistent with the 5000 collected observations"
    assert ci_lower <= true_mass, f"CI_LOWER {ci_lower} should be <= true_mass {true_mass}"
    assert ci_upper >= true_mass, f"CI_UPPER {ci_upper} should be >= true_mass {true_mass}"

    noises = [((k * 37) % 50 - 24.5) * math.sqrt(12.0) * 5.0 / 50.0 for k in range(50)]
    noise_mean = sum(noises) / 50.0
    population_variance = sum((x - noise_mean) ** 2 for x in noises) / 50.0
    bootstrap_sd = math.sqrt(sum(w * w * population_variance / 50.0 for w in weights))
    expected_half_width = 1.6448536269514722 * bootstrap_sd
    expected_lower = true_mass - expected_half_width
    expected_upper = true_mass + expected_half_width
    tolerance = max(15.0, 0.25 * expected_half_width)

    assert abs(ci_lower - expected_lower) <= tolerance, \
        f"CI_LOWER {ci_lower} is inconsistent with bootstrap resampling; expected about {expected_lower}"
    assert abs(ci_upper - expected_upper) <= tolerance, \
        f"CI_UPPER {ci_upper} is inconsistent with bootstrap resampling; expected about {expected_upper}"
PYEOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
