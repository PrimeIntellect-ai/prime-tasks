#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import subprocess

SOURCE = '/home/user/poisson.c'
BINARY = '/tmp/agent_poisson'
OUTPUT = '/home/user/center_value.txt'


def strip_comments_and_strings(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    text = re.sub(r'//[^\n]*', ' ', text)
    text = re.sub(r'"(?:\\.|[^"\\])*"', '""', text)
    text = re.sub(r"'(?:\\.|[^'\\])*'", "''", text)
    return text


def test_solver_source_compiles_and_runs():
    assert os.path.isfile(SOURCE) and not os.path.islink(SOURCE), (
        f'{SOURCE} must exist as a regular C source file.'
    )

    with open(SOURCE, 'r', encoding='utf-8', errors='replace') as f:
        raw_source = f.read()
    source = strip_comments_and_strings(raw_source)

    includes = re.findall(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', source, re.M)
    forbidden = [h for h in includes if h not in {'stdio.h', 'stdlib.h', 'math.h'}]
    assert not forbidden, f'Only stdio.h, stdlib.h, and math.h may be included; found {forbidden}.'

    # Require evidence of a genuinely fine finite-difference iteration rather
    # than a program which merely prints the known center constant.
    loop_count = len(re.findall(r'\b(?:for|while|do)\b', source))
    assert loop_count >= 2, 'The solver must contain spatial and convergence iteration loops.'

    mesh_decl = re.compile(
        r'\b(?:n|m|nx|ny|n_?x|n_?y|grid\w*|mesh\w*|points?\w*|rows?\w*|cols?\w*)\b'
        r'[^;\n]{0,100}?\b(\d+)\b',
        re.I,
    )
    mesh_sizes = [int(v) for v in mesh_decl.findall(source)]
    assert any(v >= 100 for v in mesh_sizes), (
        'The source must define a mesh dimension containing at least 100 points.'
    )

    assert re.search(r'\b(?:tol(?:erance)?|eps(?:ilon)?|diff(?:erence)?|change|delta|maxdiff|max_diff|error)\w*\b', source, re.I), (
        'The source must track a convergence change/error.'
    )
    number_tokens = re.findall(
        r'(?<![A-Za-z_])(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?[fFlL]?', source
    )
    numeric_values = []
    for token in number_tokens:
        try:
            numeric_values.append(float(token.rstrip('fFlL')))
        except ValueError:
            pass
    has_required_tolerance = any(0.0 < value <= 1.000001e-6 for value in numeric_values)
    has_pow_tolerance = bool(re.search(r'pow\s*\(\s*10(?:\.0*)?\s*,\s*-\s*6(?:\.0*)?\s*\)', source))
    assert has_required_tolerance or has_pow_tolerance, (
        'The solver must iterate using a convergence tolerance of 1e-6 or tighter.'
    )

    plus_one = set(re.findall(r'\b([A-Za-z_]\w*)\s*\+\s*1\b', source))
    minus_one = set(re.findall(r'\b([A-Za-z_]\w*)\s*-\s*1\b', source))
    assert plus_one & minus_one, (
        'No neighboring-grid-point accesses for a finite-difference stencil were found.'
    )
    assert ('[' in source) or re.search(r'\b(?:malloc|calloc)\s*\(', source), (
        'The solver must store a finite-difference mesh.'
    )

    compile_result = subprocess.run(
        ['gcc', SOURCE, '-O2', '-o', BINARY, '-lm'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f'poisson.c failed to compile:\n{compile_result.stderr}'

    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    run_result = subprocess.run(
        [BINARY],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert run_result.returncode == 0, (
        f'The compiled solver failed with status {run_result.returncode}.\n'
        f'stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}'
    )
    assert os.path.isfile(OUTPUT), (
        f'Executing the compiled solver did not create {OUTPUT}.'
    )


def test_center_value_accuracy():
    output_file = '/home/user/center_value.txt'

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    with open(output_file, 'r') as f:
        val_str = f.read().strip()

    try:
        agent_val = float(val_str)
    except ValueError:
        assert False, f"Could not parse the contents of {output_file} as a float. Found: {val_str}"

    assert math.isfinite(agent_val), f'Computed center value must be finite; found {val_str}'

    # Analytical solution at center (x=1.0, y=0.5):
    # u(1.0, 0.5) = sin(pi/2) * sinh(pi/4) / sinh(pi/2)
    target_val = math.sin(math.pi / 2.0) * math.sinh(math.pi / 4.0) / math.sinh(math.pi / 2.0)

    error = abs(agent_val - target_val)
    threshold = 0.01

    assert error < threshold, (
        f"Agent's computed center value {agent_val} is too far from the analytical "
        f"target {target_val:.5f}. Absolute error: {error:.5f} >= threshold {threshold}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
