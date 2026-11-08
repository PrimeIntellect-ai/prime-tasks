#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import struct
import subprocess
import pytest

def test_files_exist():
    """Verify that all required output files exist."""
    assert os.path.isfile('/home/user/gc_bootstrap.tsv'), "Output file /home/user/gc_bootstrap.tsv is missing."
    assert os.path.isfile('/home/user/plot.gp'), "Gnuplot script /home/user/plot.gp is missing."
    assert os.path.isfile('/home/user/gc_plot.png'), "Plot image /home/user/gc_plot.png is missing."

def test_gc_bootstrap_values():
    """Verify the mathematical correctness of gc_bootstrap.tsv using the exact LCG logic."""
    fasta_path = '/home/user/sequences.fasta'
    assert os.path.isfile(fasta_path), f"File {fasta_path} does not exist."

    seqs = []
    with open(fasta_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('>'):
                seqs.append(line)

    assert len(seqs) == 50, f"Expected 50 sequences, found {len(seqs)}."

    # LCG setup
    seed = 42
    def get_rand_idx():
        nonlocal seed
        seed = (seed * 1103515245 + 12345) % 2147483648
        return int((seed / 2147483648) * 50) + 1

    expected_results = []
    for pos in range(91):
        gc_fracs = []
        for seq in seqs:
            window = seq[pos:pos+10]
            gc_count = window.count('G') + window.count('C')
            gc_fracs.append(gc_count / 10.0)

        true_mean = sum(gc_fracs) / len(gc_fracs)

        boot_means = []
        for _ in range(100):
            sample_sum = 0.0
            for _ in range(50):
                idx = get_rand_idx() - 1  # 1-based to 0-based
                sample_sum += gc_fracs[idx]
            boot_means.append(sample_sum / 50.0)

        boot_means.sort()
        lower_ci = boot_means[2]   # 3rd value (1-based) -> index 2
        upper_ci = boot_means[97]  # 98th value (1-based) -> index 97

        expected_results.append((pos + 1, true_mean, lower_ci, upper_ci))

    tsv_path = '/home/user/gc_bootstrap.tsv'
    with open(tsv_path, 'r') as f:
        lines = [line.strip().split('\t') for line in f if line.strip()]

    assert len(lines) == 91, f"Expected 91 lines in {tsv_path}, but found {len(lines)}."

    for i, (line, exp) in enumerate(zip(lines, expected_results)):
        assert len(line) == 4, f"Line {i+1} in {tsv_path} does not have exactly 4 columns."
        pos, mean, lower, upper = map(float, line)

        exp_pos, exp_mean, exp_lower, exp_upper = exp

        assert int(pos) == exp_pos, f"Line {i+1}: Expected Position {exp_pos}, got {pos}."
        assert abs(mean - exp_mean) <= 0.0002, f"Line {i+1}: Expected Mean {exp_mean:.4f}, got {mean:.4f}."
        assert abs(lower - exp_lower) <= 0.0002, f"Line {i+1}: Expected LowerCI {exp_lower:.4f}, got {lower:.4f}."
        assert abs(upper - exp_upper) <= 0.0002, f"Line {i+1}: Expected UpperCI {exp_upper:.4f}, got {upper:.4f}."

def _strip_gnuplot_comments(text):
    cleaned = []
    for line in text.splitlines():
        out = []
        quote = None
        escaped = False
        for ch in line:
            if escaped:
                out.append(ch)
                escaped = False
            elif ch == '\\':
                out.append(ch)
                escaped = True
            elif quote:
                out.append(ch)
                if ch == quote:
                    quote = None
            elif ch in ('"', "'"):
                out.append(ch)
                quote = ch
            elif ch == '#':
                break
            else:
                out.append(ch)
        cleaned.append(''.join(out))
    return '\n'.join(cleaned)

def test_gnuplot_visualization_is_real_and_executable():
    """Require the submitted Gnuplot program to generate the requested visualization."""
    script_path = '/home/user/plot.gp'
    png_path = '/home/user/gc_plot.png'

    assert os.path.isfile(script_path), "Gnuplot script is missing."
    assert not os.path.islink(script_path), "plot.gp must be a real script file, not a symlink."
    with open(script_path, 'r', encoding='utf-8') as f:
        source = f.read()
    assert source.strip(), "plot.gp is empty."

    code = _strip_gnuplot_comments(source)
    joined = re.sub(r'\\\s*\n', ' ', code)
    lower = joined.lower()

    # The visualization must be performed by Gnuplot itself, not fabricated by
    # shelling out to another language or copying a pre-existing image.
    assert '`' not in code, "plot.gp may not execute shell commands with backticks."
    assert not re.search(r'(?im)^\s*!', code), "plot.gp may not use Gnuplot shell escapes."
    assert not re.search(r'\bsystem\s*(?:\(|\s)', lower), "plot.gp may not invoke external commands."
    assert not re.search(r'(?im)^\s*(?:load|call|eval|reread|replot)\b', lower), \
        "plot.gp must contain the visualization directly and may not load or execute other artifacts."
    assert not re.search(r'\b(?:python(?:2|3)?|perl|ruby|node|rscript)\b', lower), \
        "plot.gp references a prohibited scripting language."
    assert not re.search(r'(?i)set\s+output\s+["\']\|', joined), "Piped Gnuplot output is not allowed."

    assert re.search(r'(?i)\bset\s+term(?:inal)?\s+png(?:cairo)?\b', joined), \
        "plot.gp must select a PNG Gnuplot terminal."
    assert re.search(r'(?i)\bset\s+output\s+["\']/home/user/gc_plot\.png["\']', joined), \
        "plot.gp must write /home/user/gc_plot.png."
    assert re.search(r'(?i)\bset\s+xlabel\s+["\']Position["\']', joined), \
        'The X-axis label must be "Position".'
    assert re.search(r'(?i)\bset\s+ylabel\s+["\']GC Fraction["\']', joined), \
        'The Y-axis label must be "GC Fraction".'
    assert '/home/user/gc_bootstrap.tsv' in joined, \
        "plot.gp must read /home/user/gc_bootstrap.tsv."

    plot_commands = list(re.finditer(r'(?im)^\s*plot\b', joined))
    assert len(plot_commands) == 1, "plot.gp must contain one plot command describing the requested plot."
    plot = joined[plot_commands[0].start():]
    ci = re.search(r'(?is)\b(?:using|u)\s+\$?1\s*:\s*\$?3\s*:\s*\$?4\b.*?\bwith\s+filledcurves\b', plot)
    mean = re.search(r'(?is)\b(?:using|u)\s+\$?1\s*:\s*\$?2\b.*?\bwith\s+lines\b', plot)
    assert ci, "plot.gp must plot columns 3 and 4 as a filled confidence interval."
    assert mean, "plot.gp must plot column 2 as a mean line."
    assert ci.start() < mean.start(), "The confidence interval must be plotted behind the mean line."

    # Delete any submitted image and require Gnuplot to recreate it from the script.
    if os.path.lexists(png_path):
        os.remove(png_path)
    result = subprocess.run(
        ['/usr/bin/gnuplot', script_path],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Gnuplot failed to execute plot.gp: {result.stderr}"
    assert os.path.isfile(png_path), "Executing plot.gp did not generate gc_plot.png."
    assert not os.path.islink(png_path), "gc_plot.png must be a generated image file, not a symlink."

    with open(png_path, 'rb') as f:
        image = f.read()
    assert image.startswith(b'\x89PNG\r\n\x1a\n'), "gc_plot.png is not a PNG image."
    assert len(image) >= 1000, "Generated PNG is unexpectedly empty or trivial."
    assert len(image) >= 24 and image[12:16] == b'IHDR', "Generated PNG has no valid IHDR chunk."
    width, height = struct.unpack('>II', image[16:24])
    assert width > 0 and height > 0, "Generated PNG has invalid dimensions."
    assert b'IDAT' in image and b'IEND' in image, "Generated PNG is incomplete."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
