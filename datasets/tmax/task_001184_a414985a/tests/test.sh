#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import subprocess

VIDEO = "/app/dataset_video.mp4"
EDGES = "/home/user/edges.txt"
SOURCE = "/home/user/query.c"
EXECUTABLE = "/home/user/query"


def extract_video_edges():
    proc = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", VIDEO,
            "-vf", "scale=2:1", "-pix_fmt", "gray",
            "-f", "rawvideo", "pipe:1",
        ],
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")
    assert len(proc.stdout) == 240, (
        f"Expected exactly 120 two-byte frames, got {len(proc.stdout)} bytes"
    )
    return list(zip(proc.stdout[0::2], proc.stdout[1::2]))


def read_submitted_edges():
    with open(EDGES, "r", encoding="ascii") as f:
        lines = f.read().splitlines()
    assert len(lines) == 120, f"Expected 120 edge lines, got {len(lines)}"
    edges = []
    for number, line in enumerate(lines, 1):
        assert re.fullmatch(r"[0-9]+ [0-9]+", line), (
            f"Malformed edge on line {number}: {line!r}"
        )
        u, v = map(int, line.split(" "))
        assert 0 <= u <= 255 and 0 <= v <= 255
        edges.append((u, v))
    return edges


def expected_output(edges, queries):
    adj = [set() for _ in range(256)]
    for u, v in edges:
        adj[u].add(v)
    adj = [sorted(values) for values in adj]

    output = []
    for start, end in queries:
        if start == end:
            output.append(f"Path: {start}")
            continue

        parent = [-1] * 256
        seen = [False] * 256
        seen[start] = True
        queue = collections.deque([start])
        while queue:
            u = queue.popleft()
            for v in adj[u]:
                if not seen[v]:
                    seen[v] = True
                    parent[v] = u
                    queue.append(v)

        if not seen[end]:
            output.append("NONE")
            continue

        path = []
        current = end
        while current != -1:
            path.append(current)
            if current == start:
                break
            current = parent[current]
        path.reverse()
        output.append("Path: " + "->".join(map(str, path)))

    return "\n".join(output) + "\n"


def run_and_check(program, edges, queries):
    input_data = "".join(f"{u} {v}\n" for u, v in queries)
    proc = subprocess.run(
        [program],
        input=input_data,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, (
        f"{program} exited with {proc.returncode}: {proc.stderr}"
    )
    expected = expected_output(edges, queries)
    assert proc.stdout == expected, (
        f"Incorrect output from {program}.\n"
        f"Expected prefix: {expected[:1000]!r}\n"
        f"Actual prefix:   {proc.stdout[:1000]!r}"
    )


def test_edges_file_exists():
    assert os.path.isfile(EDGES), f"Edges file {EDGES} is missing."


def test_query_source_exists():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."


def test_query_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"Executable {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The query executable is not a compiled ELF binary."


def test_extracted_edges_match_video_exactly():
    assert read_submitted_edges() == extract_video_edges(), (
        "edges.txt does not contain the exact 120-edge sequence encoded by the video"
    )


def test_fuzz_equivalence_and_source_program():
    video_edges = extract_video_edges()
    assert read_submitted_edges() == video_edges

    compiled = "/tmp/query_from_source"
    build = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", compiled],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert build.returncode == 0, f"query.c failed to compile: {build.stderr}"

    # Preserve the original deterministic 500-query fuzz coverage, then cover
    # every valid pair so reachable paths and exact formatting are exercised.
    random.seed(42)
    fuzz_queries = [(random.randint(0, 255), random.randint(0, 255)) for _ in range(500)]
    all_queries = fuzz_queries + [(u, v) for u in range(256) for v in range(256)]
    run_and_check(EXECUTABLE, video_edges, all_queries)
    run_and_check(compiled, video_edges, all_queries)

    # Confirm both artifacts actually load edges.txt and implement directed,
    # lexicographically tie-broken shortest paths rather than hard-coding answers.
    original = open(EDGES, "rb").read()
    synthetic_edges = [(1, 3), (1, 2), (2, 4), (3, 4), (4, 5)]
    synthetic_data = b"".join(f"{u} {v}\n".encode() for u, v in synthetic_edges)
    try:
        with open(EDGES, "wb") as f:
            f.write(synthetic_data)
        queries = [(1, 4), (1, 5), (5, 1), (3, 5), (2, 2)]
        run_and_check(EXECUTABLE, synthetic_edges, queries)
        run_and_check(compiled, synthetic_edges, queries)
    finally:
        with open(EDGES, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
