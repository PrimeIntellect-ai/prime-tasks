#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile

C_FILE = "/home/user/density_sim.c"
EXE_FILE = "/home/user/density_sim"
OUT_FILE = "/home/user/reproducible_density.txt"


def compile_c(source, output):
    subprocess.run(
        ["gcc", "-fopenmp", "-O2", source, "-lm", "-o", output],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def run_program(executable, env=None):
    result = subprocess.run(
        [executable],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=30,
    )
    return result.stdout


def oracle_output(n, fmt):
    source = f'''#include <stdio.h>
#include <math.h>
int main(void) {{
    double total_density = 0.0;
    for (int i = 0; i < {n}; i++) {{
        double w = sin(i) * sin(i) + cos(i / 2.0);
        total_density += w;
    }}
    printf("{fmt}\\n", total_density);
    return 0;
}}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "oracle.c")
        exe = os.path.join(td, "oracle")
        with open(src, "w") as f:
            f.write(source)
        compile_c(src, exe)
        return run_program(exe)


def without_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    source = re.sub(r"//[^\n]*", "", source)
    return source


def test_density_sim_c_modified():
    assert os.path.exists(C_FILE), f"File {C_FILE} does not exist."

    with open(C_FILE, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "#pragma omp atomic" not in content, "The file density_sim.c still contains '#pragma omp atomic'."
    assert "compute_node_weight" in content, "The function 'compute_node_weight' is missing from density_sim.c."

    code = without_comments(content)
    assert re.search(r"#\s*pragma\s+omp\s+parallel\s+for\b", code), \
        "The compute_node_weight loop is no longer OpenMP-parallelized."
    assert re.search(r"#\s*define\s+N\s+100000\b", code), \
        "The original N definition must be retained."

    array_names = set(re.findall(r"\bdouble\s+([A-Za-z_]\w*)\s*\[\s*N\s*\]", code))
    array_names.update(re.findall(
        r"\bdouble\s*\*\s*([A-Za-z_]\w*)\s*=\s*[^;]*(?:malloc|calloc)\s*\(", code
    ))
    assert array_names, "Node weights must be stored in a double array."

    valid_array = False
    for name in array_names:
        assignment = re.search(
            rf"\b{re.escape(name)}\s*\[\s*i\s*\]\s*=\s*compute_node_weight\s*\(\s*i\s*\)",
            code,
        )
        ascending_sum = re.search(
            rf"for\s*\(\s*(?:int\s+)?i\s*=\s*0\s*;\s*i\s*<\s*N\s*;\s*(?:i\+\+|\+\+i)\s*\)\s*"
            rf"\{{[^{{}}]*\btotal_density\s*\+=\s*{re.escape(name)}\s*\[\s*i\s*\]\s*;[^{{}}]*\}}",
            code,
            flags=re.S,
        )
        if assignment and ascending_sum:
            valid_array = True
            break
    assert valid_array, \
        "Weights must be written by index and then summed sequentially from index 0 through N-1."


def test_executable_exists():
    assert os.path.exists(EXE_FILE), f"Executable {EXE_FILE} does not exist. Did you compile it?"
    assert os.access(EXE_FILE, os.X_OK), f"File {EXE_FILE} is not executable."
    with open(EXE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "density_sim must be a compiled ELF executable."


def test_output_file_and_value():
    assert os.path.exists(OUT_FILE), f"Output file {OUT_FILE} does not exist."

    with open(OUT_FILE, "r") as f:
        content = f.read().strip()

    assert content, f"File {OUT_FILE} is empty."

    try:
        actual_val = float(content)
    except ValueError:
        assert False, f"Content of {OUT_FILE} is not a valid float: {content}"

    # Preserve the original independently computed numerical assertion.
    expected_val = 0.0
    for i in range(100000):
        expected_val += math.sin(i) ** 2 + math.cos(i / 2.0)
    assert math.isclose(actual_val, expected_val, rel_tol=1e-10), \
        f"Calculated density {actual_val} does not match expected sequential sum {expected_val}."

    # Run the submitted artifact itself and recreate the requested output file.
    expected_text = oracle_output(100000, "%.10f")
    observed = []
    for threads in (1, 2, 4, 7):
        env = os.environ.copy()
        env["OMP_NUM_THREADS"] = str(threads)
        with open(OUT_FILE, "wb") as out:
            result = subprocess.run(
                [EXE_FILE], stdout=out, stderr=subprocess.PIPE, env=env,
                check=True, timeout=30,
            )
        with open(OUT_FILE, "rb") as out:
            data = out.read()
        observed.append(data)
        assert data == expected_text, \
            f"density_sim output is not the exact ascending-order result with {threads} threads."
    assert len(set(observed)) == 1, "density_sim is not reproducible across thread counts."


def test_source_on_unpredictable_sizes_with_bitwise_sum():
    with open(C_FILE, "r") as f:
        original = f.read()

    # Use unpredictable alternate sizes so a fixed precomputed answer cannot pass.
    sizes = set()
    while len(sizes) < 3:
        sizes.add(100 + secrets.randbelow(4900))

    with tempfile.TemporaryDirectory() as td:
        for n in sizes:
            candidate = re.sub(
                r"(#\s*define\s+N\s+)100000\b", rf"\g<1>{n}", original, count=1
            )
            assert candidate != original, "Could not vary N in density_sim.c."

            # Expose the exact resulting double rather than accepting decimal closeness.
            candidate, replacements = re.subn(
                r'"%\.10f\\n"', '"%a\\\\n"', candidate, count=1
            )
            assert replacements == 1, "The program must print total_density using the original printf."

            src = os.path.join(td, f"candidate_{n}.c")
            exe = os.path.join(td, f"candidate_{n}")
            with open(src, "w") as f:
                f.write(candidate)
            compile_c(src, exe)

            expected = oracle_output(n, "%a")
            outputs = []
            for threads in (1, 3, 6):
                env = os.environ.copy()
                env["OMP_NUM_THREADS"] = str(threads)
                output = run_program(exe, env)
                outputs.append(output)
                assert output == expected, \
                    f"For N={n}, accumulation is not bitwise equal to an ascending-index sum."
            assert len(set(outputs)) == 1, f"For N={n}, output changes with thread count."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
