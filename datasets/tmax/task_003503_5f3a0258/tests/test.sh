#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/simulate_walk.sh"
NETWORK_PATH = "/home/user/ppi_network.tsv"

AWK_REF = r'''BEGIN {
    FS="\t"
    if (seed != "") srand(seed)
}
{
    src = $1; dst = $2; weight = $3
    edges[src][dst] = weight
    nodes[src] = 1
    nodes[dst] = 1
}
END {
    curr = start
    for (step=1; step<=1000; step++) {
        max_score = -1
        best_dst = ""

        n_dst = asorti(edges[curr], sorted_dsts)
        if (n_dst > 0) {
            for (i=1; i<=n_dst; i++) {
                v = sorted_dsts[i]
                r = rand()
                score = edges[curr][v] * r

                if (score > max_score) {
                    max_score = score
                    best_dst = v
                } else if (score == max_score) {
                    if (best_dst == "" || v < best_dst) {
                        best_dst = v
                    }
                }
            }
            curr = best_dst
        }
        visits[curr]++
    }

    n_vis = asorti(visits, sorted_visits)
    for (i=1; i<=n_vis; i++) {
        p = sorted_visits[i]
        count = visits[p]
        bars = ""
        num_bars = int(count / 10)
        for (b=0; b<num_bars; b++) bars = bars "="
        printf "%s [%d] : %s\n", p, count, bars
    }
}
'''


def get_expected_output(start, seed):
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as f:
        f.write(AWK_REF)
        ref_path = f.name
    try:
        res = subprocess.run(
            ["awk", "-v", f"start={start}", "-v", f"seed={seed}",
             "-f", ref_path, NETWORK_PATH],
            capture_output=True, text=True, check=True, timeout=15,
        )
        return res.stdout.strip()
    finally:
        os.remove(ref_path)


def run_submission(start, seed):
    return subprocess.run(
        [SCRIPT_PATH, start, str(seed)],
        capture_output=True, text=True, timeout=15,
    )


def assert_correct(start, seed):
    expected = get_expected_output(start, str(seed))
    res = run_submission(start, seed)
    assert res.returncode == 0, (
        f"Script failed for start={start}, seed={seed} with return code "
        f"{res.returncode}. Stderr: {res.stderr}"
    )
    assert res.stdout.strip() == expected, (
        f"Output mismatch for start={start}, seed={seed}.\n"
        f"Expected:\n{expected}\n\nActual:\n{res.stdout.strip()}"
    )


def test_script_exists_executable_and_uses_bash_awk():
    assert os.path.isfile(SCRIPT_PATH), f"Missing required script: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"

    with open(SCRIPT_PATH, "r", errors="replace") as f:
        text = f.read()
    first_line = text.splitlines()[0] if text.splitlines() else ""
    assert re.match(r"^#!.*(?:/|\s)bash(?:\s|$)", first_line), \
        "The executable must be a Bash script"
    assert re.search(r"(?<![A-Za-z0-9_])awk(?![A-Za-z0-9_])", text), \
        "The simulation must be implemented with awk"
    assert re.search(r"\bsrand\s*\(", text), "awk logic must seed its RNG with srand"
    assert re.search(r"\brand\s*\(", text), "awk logic must use rand()"
    assert not re.search(r"\b(?:python[0-9.]*|perl|ruby|node|php|Rscript)\b", text, re.I), \
        "Only Bash, awk, and GNU coreutils are permitted"


def test_exact_argument_count():
    bad_argv = [[], ["A"], ["A", "42", "extra"]]
    for args in bad_argv:
        res = subprocess.run([SCRIPT_PATH] + args, capture_output=True,
                             text=True, timeout=15)
        assert res.returncode != 0, \
            f"Script must reject argument list: {args!r}"


@pytest.mark.parametrize("start,seed", [
    ("A", "42"),
    ("E", "100"),
    ("C", "999"),
])
def test_original_cases(start, seed):
    assert_correct(start, seed)


def test_private_seeds_and_starts_on_supplied_network():
    rng = secrets.SystemRandom()
    cases = [(rng.choice(list("ABCDE")), rng.randrange(1, 2**31))
             for _ in range(10)]
    # A previously unseen protein has no outgoing edges and must remain in place.
    cases.append(("NO_OUT_" + secrets.token_hex(5), rng.randrange(1, 2**31)))
    for start, seed in cases:
        assert_correct(start, seed)


def test_private_generated_network():
    rng = secrets.SystemRandom()
    token = secrets.token_hex(3).upper()
    names = [f"P{token}_{i}" for i in range(7)]
    lines = []

    # Give every node three outgoing edges in deliberately unsorted file order.
    for src in names:
        destinations = rng.sample(names, 3)
        rng.shuffle(destinations)
        for dst in destinations:
            weight = rng.randrange(1, 1000) / 1000.0
            lines.append(f"{src}\t{dst}\t{weight:.3f}\n")

    # Exercise a deterministic score tie and subsequent no-outgoing behavior.
    tie = "TIE_" + token
    alpha = "AA_SINK_" + token
    omega = "ZZ_SINK_" + token
    lines.extend([
        f"{tie}\t{omega}\t0\n",
        f"{tie}\t{alpha}\t0\n",
    ])

    with open(NETWORK_PATH, "rb") as f:
        original = f.read()
    original_mode = os.stat(NETWORK_PATH).st_mode

    try:
        with open(NETWORK_PATH, "w") as f:
            f.writelines(lines)

        cases = [(rng.choice(names), rng.randrange(1, 2**31)) for _ in range(8)]
        cases.append((tie, rng.randrange(1, 2**31)))
        cases.append(("ABSENT_" + token, rng.randrange(1, 2**31)))
        for start, seed in cases:
            assert_correct(start, seed)
    finally:
        with open(NETWORK_PATH, "wb") as f:
            f.write(original)
        os.chmod(NETWORK_PATH, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
