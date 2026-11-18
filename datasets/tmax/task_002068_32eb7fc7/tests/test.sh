#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import time

APP_DIR = "/home/user/app"
SOURCE_FILE = os.path.join(APP_DIR, "mesh_align.c")
OBSERVATIONS_FILE = os.path.join(APP_DIR, "observations.csv")
OPT_EXEC_FILE = os.path.join(APP_DIR, "mesh_align_opt")
OUTPUT_FILE = os.path.join(APP_DIR, "top_nodes.txt")
COMPILED_SOURCE_FILE = "/tmp/mesh_align_from_source"
PRIMER = "ATGCGTACGTTAGC"


def fail(message):
    raise AssertionError(message)


def score_sequence(seq):
    return sum(10 for i in range(min(len(PRIMER), len(seq))) if PRIMER[i] == seq[i])


def read_observations():
    if not os.path.isfile(OBSERVATIONS_FILE):
        fail(f"Missing observations file: {OBSERVATIONS_FILE}")

    nodes = []
    with open(OBSERVATIONS_FILE, "r") as f:
        for order, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) < 4:
                fail(f"Malformed observations line: {line}")
            node_id = int(parts[0])
            seq = parts[3]
            nodes.append((order, node_id, score_sequence(seq)))
    return nodes


def expected_top_nodes():
    nodes = read_observations()
    # Python's sort is stable, matching the original stable bubble sort for ties.
    nodes.sort(key=lambda item: item[2], reverse=True)
    return [(node_id, score) for _, node_id, score in nodes[:5]]


def parse_and_validate_output():
    if not os.path.isfile(OUTPUT_FILE):
        fail(f"Output file {OUTPUT_FILE} is missing after execution")

    with open(OUTPUT_FILE, "r") as f:
        raw_lines = f.readlines()

    if len(raw_lines) != 5:
        fail(f"Expected exactly 5 lines in {OUTPUT_FILE}, found {len(raw_lines)}")

    parsed = []
    pattern = re.compile(r"NodeID: (-?\d+), Score: (-?\d+)\n?\Z")
    for line in raw_lines:
        match = pattern.fullmatch(line)
        if not match:
            fail(f"Line format incorrect: {line.rstrip()!r}")
        parsed.append((int(match.group(1)), int(match.group(2))))

    if len({node_id for node_id, _ in parsed}) != 5:
        fail("The five output NodeIDs must be unique")

    expected = expected_top_nodes()
    if parsed != expected:
        fail(f"Expected ordered top nodes {expected}, but got {parsed}")


def run_and_check(executable):
    try:
        os.unlink(OUTPUT_FILE)
    except FileNotFoundError:
        pass

    start = time.monotonic()
    try:
        result = subprocess.run(
            [executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=1.0,
            check=False,
        )
    except subprocess.TimeoutExpired:
        fail(f"{executable} did not finish in under 1 second")
    elapsed = time.monotonic() - start

    if result.returncode != 0:
        fail(
            f"{executable} exited with status {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
    if elapsed >= 1.0:
        fail(f"{executable} took {elapsed:.3f}s; required runtime is under 1 second")

    parse_and_validate_output()


def verify_source_was_optimized():
    if not os.path.isfile(SOURCE_FILE):
        fail(f"Missing optimized source file: {SOURCE_FILE}")

    with open(SOURCE_FILE, "r", errors="replace") as f:
        source = f.read()

    # Strip comments and whitespace so comments or formatting alone cannot count
    # as optimizing the supplied implementation.
    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    compact = re.sub(r"\s+", "", without_comments)

    old_sequence_loops = (
        "for(size_ti=0;i<strlen(target);i++)",
        "for(size_tj=0;j<strlen(query);j++)",
    )
    for loop in old_sequence_loops:
        if loop in compact:
            fail("mesh_align.c still contains the supplied repeated-strlen scoring bottleneck")

    old_bubble_sort = (
        "for(inti=0;i<node_count-1;i++){"
        "for(intj=0;j<node_count-i-1;j++)"
    )
    if old_bubble_sort in compact:
        fail("mesh_align.c still contains the supplied quadratic bubble-sort bottleneck")

    result = subprocess.run(
        ["gcc", "-O2", SOURCE_FILE, "-o", COMPILED_SOURCE_FILE, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        fail("mesh_align.c does not compile: " + result.stderr.decode(errors="replace"))


def write_challenge_observations():
    rng = random.Random(731947)
    forced_best = {3, 17, 400, 999, 1500, 1998}
    with open(OBSERVATIONS_FILE, "w") as f:
        for i in range(2000):
            # A permutation makes NodeID order differ from input order, exposing
            # incorrect tie-breaking while retaining unique IDs.
            node_id = 10000 + ((i * 997) % 2000)
            seq = "".join(rng.choice("ACGT") for _ in range(150))
            if i in forced_best:
                seq = PRIMER + seq[len(PRIMER):]
            f.write(f"{node_id},{(i * 0.37) % 100:.2f},{(i * 0.61) % 100:.2f},{seq}\n")


def main():
    if not os.path.isfile(OPT_EXEC_FILE):
        fail(f"Optimized executable {OPT_EXEC_FILE} is missing")
    if not os.access(OPT_EXEC_FILE, os.X_OK):
        fail(f"File {OPT_EXEC_FILE} is not executable")
    with open(OPT_EXEC_FILE, "rb") as f:
        if f.read(4) != b"\x7fELF":
            fail("mesh_align_opt must be a compiled native executable")

    verify_source_was_optimized()

    with open(OBSERVATIONS_FILE, "rb") as f:
        original_observations = f.read()

    try:
        # Exercise both the submitted executable and an independently compiled
        # build of the submitted C source on verifier-generated data.
        write_challenge_observations()
        run_and_check(COMPILED_SOURCE_FILE)
        run_and_check(OPT_EXEC_FILE)
    finally:
        with open(OBSERVATIONS_FILE, "wb") as f:
            f.write(original_observations)
        try:
            os.unlink(OUTPUT_FILE)
        except FileNotFoundError:
            pass

    # Finally run the requested artifact on the real input, validate it, and
    # leave top_nodes.txt in the requested final state.
    run_and_check(OPT_EXEC_FILE)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
