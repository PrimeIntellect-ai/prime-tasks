#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

SCRIPT = "/home/user/fit_mixture.py"
FASTA = "/home/user/community.fasta"
OUTPUT = "/home/user/optimal_weight.txt"
BASES = "ACGT"


def read_output():
    assert os.path.isfile(OUTPUT), f"Missing output file: {OUTPUT}"
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert re.fullmatch(r"(?:0|1)\.\d{3}", content), (
        f"Output must be a weight with exactly 3 decimal places, got {content!r}"
    )
    return content


def run_script(expected):
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"fit_mixture.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = read_output()
    assert actual == expected, f"Expected {expected!r}, but got {actual!r}"


def write_fasta(target, source1, source2):
    def sequence(counts):
        return "".join(base * count for base, count in zip(BASES, counts))

    with open(FASTA, "w") as f:
        f.write(">Target\n" + sequence(target) + "\n")
        f.write(">Source1\n" + sequence(source1) + "\n")
        f.write(">Source2\n" + sequence(source2) + "\n")


def random_counts(total=100):
    cuts = sorted(secrets.SystemRandom().sample(range(1, total), 3))
    return (cuts[0], cuts[1] - cuts[0], cuts[2] - cuts[1], total - cuts[2])


def expected_weight(target, source1, source2):
    target_total = sum(target)
    source1_total = sum(source1)
    source2_total = sum(source2)
    t = [x / target_total for x in target]
    s1 = [x / source1_total for x in source1]
    s2 = [x / source2_total for x in source2]
    delta = [a - b for a, b in zip(s1, s2)]
    denominator = sum(x * x for x in delta)
    assert denominator > 0
    w = sum((a - b) * d for a, b, d in zip(t, s2, delta)) / denominator
    return min(1.0, max(0.0, w))


def main():
    # Preserve all original final-state assertions.
    assert os.path.isfile(SCRIPT), f"Missing script file: {SCRIPT}"
    assert os.path.getsize(SCRIPT) > 0, f"Script is empty: {SCRIPT}"
    assert os.path.isfile(OUTPUT), f"Missing output file: {OUTPUT}"
    assert read_output() == "0.800", f"Expected '0.800' in {OUTPUT}"

    with open(FASTA, "r") as f:
        original_fasta = f.read()

    try:
        # Execute the submitted artifact on the supplied input and require it to
        # recreate the deleted output rather than accepting a stale constant.
        run_script("0.800")

        # Exercise the same calculation on unpredictable FASTA contents. The
        # verifier independently derives the constrained least-squares answer.
        tested = 0
        while tested < 4:
            target = random_counts()
            source1 = random_counts()
            source2 = random_counts()
            if source1 == source2:
                continue
            w = expected_weight(target, source1, source2)
            scaled = w * 1000
            # Avoid numerical and rounding-boundary ambiguity.
            if not (0.03 < w < 0.97):
                continue
            if abs(scaled - (math.floor(scaled) + 0.5)) < 0.1:
                continue
            expected = f"{w:.3f}"
            if expected == "0.800":
                continue
            write_fasta(target, source1, source2)
            run_script(expected)
            tested += 1
    finally:
        # Restore the task input and require the final output to retain the
        # originally asserted value.
        with open(FASTA, "w") as f:
            f.write(original_fasta)
        run_script("0.800")


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
