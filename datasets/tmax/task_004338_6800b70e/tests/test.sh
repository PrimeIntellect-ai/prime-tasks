#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest
import numpy as np
from PIL import Image


def get_reverse_complement(seq):
    complement = {'A': 'T', 'C': 'G', 'G': 'C', 'T': 'A'}
    return "".join(complement.get(base, base) for base in reversed(seq))


def compute_truth():
    fasta_path = "/home/user/aligned_sequences.fasta"
    if not os.path.exists(fasta_path):
        return None

    with open(fasta_path, "r") as f:
        lines = f.readlines()

    seqs = []
    current_seq = []
    for line in lines:
        line = line.strip()
        if line.startswith(">"):
            if current_seq:
                seqs.append("".join(current_seq).upper())
                current_seq = []
        else:
            current_seq.append(line)
    if current_seq:
        seqs.append("".join(current_seq).upper())

    if not seqs:
        return None

    seq_len = len(seqs[0])
    num_seqs = len(seqs)

    conserved = [False] * seq_len
    for i in range(seq_len):
        first_char = seqs[0][i]
        is_conserved = True
        for j in range(1, num_seqs):
            if seqs[j][i] != first_char:
                is_conserved = False
                break
        conserved[i] = is_conserved

    domains = []

    def refine(start, end):
        length = end - start
        cons_count = sum(conserved[start:end])
        ratio = cons_count / length

        if length <= 25 or ratio < 0.70:
            domains.append((start, end, ratio))
        else:
            mid = start + length // 2
            refine(start, mid)
            refine(mid, end)

    for start in range(0, seq_len, 200):
        refine(start, start + 200)

    num_final_domains = len(domains)
    candidates = [d for d in domains if (d[1] - d[0] == 25) and d[2] >= 0.90]

    if not candidates:
        return None

    forward_domain = min(candidates, key=lambda x: x[0])
    reverse_domain = max(candidates, key=lambda x: x[0])

    forward_primer = seqs[0][forward_domain[0]:forward_domain[1]]
    reverse_primer_fwd = seqs[0][reverse_domain[0]:reverse_domain[1]]
    reverse_primer = get_reverse_complement(reverse_primer_fwd)

    return {
        "num_final_domains": num_final_domains,
        "forward_primer": forward_primer,
        "reverse_primer": reverse_primer,
        "domains": domains,
        "forward_region": (forward_domain[0], forward_domain[1]),
        "reverse_region": (reverse_domain[0], reverse_domain[1]),
        "seq_len": seq_len,
    }


def test_json_results():
    """Test that analysis_results.json exists and contains the correct results."""
    json_path = "/home/user/analysis_results.json"
    assert os.path.exists(json_path), f"File {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    truth = compute_truth()
    assert truth is not None, "Could not compute truth from FASTA."

    assert "num_final_domains" in results, "Missing 'num_final_domains' in JSON."
    assert "forward_primer" in results, "Missing 'forward_primer' in JSON."
    assert "reverse_primer" in results, "Missing 'reverse_primer' in JSON."

    assert results["num_final_domains"] == truth["num_final_domains"], \
        f"Expected num_final_domains={truth['num_final_domains']}, got {results['num_final_domains']}."
    assert results["forward_primer"] == truth["forward_primer"], \
        f"Expected forward_primer={truth['forward_primer']}, got {results['forward_primer']}."
    assert results["reverse_primer"] == truth["reverse_primer"], \
        f"Expected reverse_primer={truth['reverse_primer']}, got {results['reverse_primer']}."


def test_plot_exists():
    """Test that the conservation_mesh.png plot exists."""
    plot_path = "/home/user/conservation_mesh.png"
    assert os.path.exists(plot_path), f"Plot file {plot_path} does not exist."
    assert os.path.isfile(plot_path), f"Path {plot_path} is not a file."
    assert os.path.getsize(plot_path) > 0, f"Plot file {plot_path} is empty."


def test_plot_contains_mesh_and_primer_highlights():
    """Validate that the PNG contains the requested mesh and primer annotations."""
    plot_path = "/home/user/conservation_mesh.png"
    truth = compute_truth()
    assert truth is not None, "Could not compute truth from FASTA."

    try:
        with Image.open(plot_path) as check_image:
            assert check_image.format == "PNG", "conservation_mesh.png is not a PNG image."
            check_image.verify()
        with Image.open(plot_path) as source:
            rgba = np.asarray(source.convert("RGBA"), dtype=np.float32)
    except Exception as exc:
        pytest.fail(f"conservation_mesh.png is not a decodable PNG: {exc}")

    height, width = rgba.shape[:2]
    assert width >= 200 and height >= 120, "Plot is too small to visualize the 1000 bp mesh."

    alpha = rgba[:, :, 3:4] / 255.0
    rgb = rgba[:, :, :3] * alpha + 255.0 * (1.0 - alpha)
    assert np.std(rgb) > 8.0, "Plot is visually blank or nearly uniform."

    # Long, locally contrasting vertical strokes are the raster signature of
    # mesh-boundary lines. Locate an affine genome-to-image mapping rather than
    # assuming a particular matplotlib margin or figure size.
    y0, y1 = int(height * 0.07), int(height * 0.90)
    vertical_strength = np.zeros(width, dtype=np.int32)
    for x in range(6, width - 6):
        best = 0
        for dx in (-2, -1, 0, 1, 2):
            center = rgb[y0:y1, x + dx]
            left = rgb[y0:y1, x + dx - 5]
            right = rgb[y0:y1, x + dx + 5]
            contrast = np.minimum(
                np.linalg.norm(center - left, axis=1),
                np.linalg.norm(center - right, axis=1),
            )
            best = max(best, int(np.count_nonzero(contrast > 28.0)))
        vertical_strength[x] = best

    boundaries = sorted({d[0] for d in truth["domains"]} | {d[1] for d in truth["domains"]})
    internal_boundaries = [b for b in boundaries if 0 < b < truth["seq_len"]]
    line_threshold = max(8, int((y1 - y0) * 0.11))
    tolerance = max(2, int(width * 0.004))

    best_match = (-1, None, None)
    for left_edge in range(int(width * 0.04), int(width * 0.26) + 1, 2):
        for right_edge in range(int(width * 0.74), int(width * 0.98) + 1, 2):
            if right_edge - left_edge < width * 0.45:
                continue
            matches = 0
            for boundary in internal_boundaries:
                x = left_edge + (right_edge - left_edge) * boundary / truth["seq_len"]
                lo = max(0, int(round(x)) - tolerance)
                hi = min(width, int(round(x)) + tolerance + 1)
                if np.max(vertical_strength[lo:hi], initial=0) >= line_threshold:
                    matches += 1
            if matches > best_match[0]:
                best_match = (matches, left_edge, right_edge)

    required_matches = max(4, int(np.ceil(len(internal_boundaries) * 0.55)))
    assert best_match[0] >= required_matches, (
        "Plot does not show vertical boundaries aligned with the final refined mesh "
        f"(found {best_match[0]} of {len(internal_boundaries)} expected boundaries)."
    )

    left_edge, right_edge = best_match[1], best_match[2]

    def region_is_highlighted(region):
        start, end = region
        x_start = int(round(left_edge + (right_edge - left_edge) * start / truth["seq_len"]))
        x_end = int(round(left_edge + (right_edge - left_edge) * end / truth["seq_len"]))
        if x_end <= x_start:
            x_end = x_start + 1
        span = max(2, x_end - x_start)
        gap = max(2, tolerance)
        xa, xb = max(0, x_start), min(width, x_end)
        la, lb = max(0, xa - gap - span), max(0, xa - gap)
        ra, rb = min(width, xb + gap), min(width, xb + gap + span)
        target = rgb[y0:y1, xa:xb]
        if target.size == 0 or lb <= la or rb <= ra:
            return False

        left = rgb[y0:y1, la:lb]
        right = rgb[y0:y1, ra:rb]
        target_rows = target.mean(axis=1)
        flank_rows = (left.mean(axis=1) + right.mean(axis=1)) / 2.0
        changed_rows = np.count_nonzero(np.linalg.norm(target_rows - flank_rows, axis=1) > 12.0)
        shaded = changed_rows >= max(5, int((y1 - y0) * 0.12))

        target_chroma = target.max(axis=2) - target.min(axis=2)
        left_chroma = left.max(axis=2) - left.min(axis=2)
        right_chroma = right.max(axis=2) - right.min(axis=2)
        target_colored = int(np.count_nonzero(target_chroma > 50.0))
        flank_density = (
            np.count_nonzero(left_chroma > 50.0) / left_chroma.size
            + np.count_nonzero(right_chroma > 50.0) / right_chroma.size
        ) / 2.0
        expected_flank_colored = flank_density * target_chroma.size
        colored_bar = target_colored - expected_flank_colored >= max(12, target_chroma.size * 0.002)
        return shaded or colored_bar

    assert region_is_highlighted(truth["forward_region"]), \
        "The selected Forward primer region is not visibly highlighted in the plot."
    assert region_is_highlighted(truth["reverse_region"]), \
        "The selected Reverse primer region is not visibly highlighted in the plot."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
