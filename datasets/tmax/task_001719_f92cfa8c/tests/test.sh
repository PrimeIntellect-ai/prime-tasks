#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import subprocess
import tempfile
import uuid

import pytest
from PIL import Image, ImageEnhance, ImageOps

EXECUTABLE_PATH = "/home/user/filter"
GRAPH_IMAGE_PATH = "/app/hub_graph.png"


def test_filter_executable_exists():
    """Verify that the compiled Go program exists at the required location."""
    assert os.path.isfile(EXECUTABLE_PATH), f"Executable not found at {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable"


def test_adversarial_corpus():
    """Retain the original checks against the supplied clean and evil corpora."""
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    clean_failed = []
    for filepath in clean_files:
        result = subprocess.run([EXECUTABLE_PATH, filepath], capture_output=True, timeout=10)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(filepath))

    evil_failed = []
    for filepath in evil_files:
        result = subprocess.run([EXECUTABLE_PATH, filepath], capture_output=True, timeout=10)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(filepath))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean files rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil files bypassed: {', '.join(evil_failed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def extract_edges_from_image():
    """OCR the canonical image and derive the directed edge set from its contents."""
    assert os.path.isfile(GRAPH_IMAGE_PATH), f"Graph image missing at {GRAPH_IMAGE_PATH}"
    image = Image.open(GRAPH_IMAGE_PATH).convert("L")
    inverted = ImageOps.invert(image)
    bbox = inverted.getbbox()
    assert bbox is not None, "Graph image contains no visible topology"
    cropped = image.crop(bbox)

    variants = [
        cropped.resize((cropped.width * 6, cropped.height * 6), Image.Resampling.LANCZOS),
        cropped.resize((cropped.width * 8, cropped.height * 8), Image.Resampling.NEAREST),
    ]
    variants.append(ImageEnhance.Contrast(variants[0]).enhance(2.0).point(lambda p: 255 if p > 180 else 0))

    edge_pattern = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*[-=~—–]*>\s*([A-Z][A-Z0-9_]*)\s*$")
    candidates = []
    with tempfile.TemporaryDirectory(prefix="graph_ocr_") as td:
        for index, variant in enumerate(variants):
            path = os.path.join(td, f"variant_{index}.png")
            variant.save(path)
            result = subprocess.run(
                ["tesseract", path, "stdout", "--psm", "6"],
                text=True,
                capture_output=True,
                timeout=30,
                check=True,
            )
            edges = set()
            for line in result.stdout.upper().splitlines():
                match = edge_pattern.match(line)
                if match:
                    edges.add((match.group(1), match.group(2)))
            if edges:
                candidates.append(frozenset(edges))

    assert candidates, "OCR did not recover any directed edges from the graph image"
    counts = collections.Counter(candidates)
    edges = set(max(counts, key=lambda candidate: (counts[candidate], len(candidate))))
    nodes = {node for edge in edges for node in edge}
    assert len(edges) >= 5 and len(nodes) >= 5, "OCR recovered an implausibly small graph"
    return edges, nodes


def random_walk(edges, rng, maximum_steps=8):
    outgoing = collections.defaultdict(list)
    for source, destination in edges:
        outgoing[source].append(destination)
    start = rng.choice(sorted(outgoing))
    route = [start]
    for _ in range(rng.randint(1, maximum_steps)):
        choices = outgoing.get(route[-1])
        if not choices:
            break
        route.append(rng.choice(choices))
    return route


def test_routes_generated_from_ocr_topology():
    """Exercise randomized files whose expected results come from the OCR-derived graph."""
    edges, nodes = extract_edges_from_image()
    nonedges = [(a, b) for a in nodes for b in nodes if a != b and (a, b) not in edges]
    assert nonedges, "Canonical graph unexpectedly contains every possible directed edge"

    rng = random.SystemRandom()
    cases = []

    # Every recovered edge must be accepted, both alone and in aggregate.
    edge_routes = [[source, destination] for source, destination in sorted(edges)]
    cases.append((edge_routes, 0))
    for route in edge_routes:
        cases.append(([route], 0))

    # Add unpredictable valid multi-hop walks.
    for _ in range(8):
        cases.append(([random_walk(edges, rng) for _ in range(rng.randint(2, 7))], 0))

    # Exercise every absent transition, mixed with otherwise valid routes.
    rng.shuffle(nonedges)
    for source, destination in nonedges:
        routes = [random_walk(edges, rng) for _ in range(rng.randint(1, 4))]
        routes.insert(rng.randrange(len(routes) + 1), [source, destination])
        cases.append((routes, 1))

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix=f"route_inputs_{uuid.uuid4().hex}_") as td:
        materialized = []
        for routes, expected in cases:
            path = os.path.join(td, uuid.uuid4().hex + ".txt")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write("\n".join(",".join(route) for route in routes) + "\n")
            materialized.append((path, expected))

        for path, expected in materialized:
            result = subprocess.run([EXECUTABLE_PATH, path], capture_output=True, timeout=10)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)} returned {result.returncode}, expected {expected}"
                )

    assert not failures, "Generated topology tests failed: " + " | ".join(failures[:10])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
