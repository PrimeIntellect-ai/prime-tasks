#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import math
import os
import re
import subprocess
import tempfile

C_PATH = '/home/user/svd_sim.c'
PIPELINE_PATH = '/home/user/pipeline.sh'


def expected_sigma(sin_fn=math.sin, cos_fn=math.cos, exp_fn=math.exp):
    sum_spatial_sq = 0.0
    for x in range(100):
        for y in range(100):
            val = sin_fn(math.pi * x / 100.0) * cos_fn(math.pi * y / 100.0)
            sum_spatial_sq += val * val

    sum_temporal_sq = 0.0
    for t in range(10):
        val = exp_fn(-0.1 * t)
        sum_temporal_sq += val * val

    return math.sqrt(sum_spatial_sq) * math.sqrt(sum_temporal_sq)


def compile_and_run(extra_sources=None, extra_link_args=None):
    extra_sources = extra_sources or []
    extra_link_args = extra_link_args or []
    build_dir = tempfile.mkdtemp(prefix='svd_verify_')
    executable = os.path.join(build_dir, 'svd_sim')
    command = [
        'gcc', '-std=c11', '-O0', '-fno-builtin',
        '-Wall', '-Wextra', '-Werror=implicit-function-declaration',
        C_PATH, *extra_sources, '-o', executable, *extra_link_args, '-lm'
    ]
    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"svd_sim.c did not compile with standard gcc and -lm.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    sv_path = '/home/user/singular_value.txt'
    if os.path.exists(sv_path):
        os.remove(sv_path)
    result = subprocess.run([executable], cwd='/home/user', capture_output=True,
                            text=True, timeout=30)
    assert result.returncode == 0, (
        f"Independently compiled C program failed.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(sv_path), 'The independently compiled C program did not create singular_value.txt'
    with open(sv_path, 'r') as f:
        return f.read().strip()


def test_c_program_exists():
    """Check that the C program exists."""
    assert os.path.isfile(C_PATH), "/home/user/svd_sim.c does not exist"


def test_pipeline_script_exists_and_executable():
    """Check that the pipeline script exists and is executable."""
    assert os.path.isfile(PIPELINE_PATH), f"{PIPELINE_PATH} does not exist"
    assert os.access(PIPELINE_PATH, os.X_OK), f"{PIPELINE_PATH} is not executable"


def test_source_uses_only_permitted_headers_and_contains_power_iteration():
    with open(C_PATH, 'r') as f:
        source = f.read()

    without_comments = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    without_comments = re.sub(r'//.*', '', without_comments)

    includes = re.findall(r'^\s*#\s*include\s+(.+?)\s*$', without_comments, flags=re.M)
    allowed = {'<stdio.h>', '<stdlib.h>', '<math.h>', '"stdio.h"', '"stdlib.h"', '"math.h"'}
    assert includes, 'svd_sim.c does not include the required standard C headers'
    assert all(item in allowed for item in includes), f'Only stdio.h, stdlib.h, and math.h may be included; found {includes}'

    assert re.search(r'\bsin\s*\(', without_comments), 'The scalar field must be generated with sin'
    assert re.search(r'\bcos\s*\(', without_comments), 'The scalar field must be generated with cos'
    assert re.search(r'\bexp\s*\(', without_comments), 'The scalar field must be generated with exp'
    assert re.search(r'\b100\b', without_comments) and re.search(r'\b10\b', without_comments), \
        'The required 100x100 grid and 10 time steps are not represented in the C source'

    loop_headers = re.findall(r'\b(?:for|while)\s*\([^)]*\)', without_comments, flags=re.S)
    assert any(re.search(r'\b(?:50|49)\b', header) for header in loop_headers), \
        'No power-iteration loop with an exact 50-iteration bound was found'
    assert re.search(r'=\s*1(?:\.0*)?\s*;', without_comments), \
        'The source does not initialize the power-iteration vector to ones'

    fixed_answer = f"{expected_sigma():.4f}"
    assert fixed_answer not in without_comments, 'The expected singular value is hard-coded in svd_sim.c'


def test_pipeline_contains_compile_and_execution_steps():
    with open(PIPELINE_PATH, 'r') as f:
        script = f.read()
    normalized = script.replace('\\\n', ' ')
    compile_lines = [line for line in normalized.splitlines()
                     if re.search(r'(^|[;&|]\s*|\s)gcc\s', line) and 'svd_sim.c' in line]
    assert compile_lines, 'pipeline.sh does not compile svd_sim.c with gcc'
    compile_text = ' '.join(compile_lines)
    assert '-lm' in compile_text, 'pipeline.sh does not link the C program with -lm'

    output_match = re.search(r'-o\s+([^\s;&|]+)', compile_text)
    if output_match:
        output_token = output_match.group(1).strip("'\"")
        assert normalized.count(output_token) >= 2, 'pipeline.sh does not execute the binary produced by gcc'
    else:
        assert re.search(r'(^|[;&|\n]\s*)\.?/?a\.out(?:\s|$)', normalized), \
            'pipeline.sh does not execute gcc\'s default a.out binary'


def test_independently_compiled_c_program():
    actual = compile_and_run()
    expected = f"{expected_sigma():.4f}"
    assert actual == expected, f"Expected independently compiled C program to write {expected}, but got {actual}"


def test_c_program_recomputes_from_the_field():
    wrapper_source = r'''
extern double __real_sin(double);
extern double __real_cos(double);
extern double __real_exp(double);

double __wrap_sin(double x) { return 1.03125 * __real_sin(x) + 0.007; }
double __wrap_cos(double x) { return 0.96875 * __real_cos(x) - 0.011; }
double __wrap_exp(double x) { return 1.0625 * __real_exp(x) + 0.003; }
'''
    with tempfile.NamedTemporaryFile(mode='w', suffix='.c', delete=False) as f:
        f.write(wrapper_source)
        wrapper_path = f.name
    try:
        actual = compile_and_run(
            [wrapper_path],
            ['-Wl,--wrap=sin', '-Wl,--wrap=cos', '-Wl,--wrap=exp']
        )
    finally:
        os.unlink(wrapper_path)

    sin_fn = lambda x: 1.03125 * math.sin(x) + 0.007
    cos_fn = lambda x: 0.96875 * math.cos(x) - 0.011
    exp_fn = lambda x: 1.0625 * math.exp(x) + 0.003
    expected = f"{expected_sigma(sin_fn, cos_fn, exp_fn):.4f}"
    assert actual == expected, (
        'The C program does not recompute the singular value from the generated field; '
        f'under instrumented math functions expected {expected}, but got {actual}'
    )


def test_pipeline_execution_and_outputs():
    """Run the pipeline script and verify the outputs."""
    with open(C_PATH, 'rb') as f:
        source_hash = hashlib.sha256(f.read()).digest()

    result = subprocess.run([PIPELINE_PATH], cwd='/home/user', capture_output=True,
                            text=True, timeout=60)
    assert result.returncode == 0, f"Pipeline script failed with return code {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"

    with open(C_PATH, 'rb') as f:
        assert hashlib.sha256(f.read()).digest() == source_hash, 'pipeline.sh modified svd_sim.c while running'

    expected_str = f"{expected_sigma():.4f}"

    sv_path = '/home/user/singular_value.txt'
    assert os.path.isfile(sv_path), f"{sv_path} was not created"
    with open(sv_path, 'r') as f:
        sv_content = f.read().strip()
    assert sv_content == expected_str, f"Expected singular value {expected_str}, but got {sv_content}"

    nb_path = '/home/user/notebook.md'
    assert os.path.isfile(nb_path), f"{nb_path} was not created"
    with open(nb_path, 'r') as f:
        nb_content = f.read()

    expected_nb_string = f"The dominant singular value is: {expected_str}"
    assert expected_nb_string in nb_content, f"Expected string '{expected_nb_string}' not found in {nb_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
