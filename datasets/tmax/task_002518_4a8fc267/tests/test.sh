#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import re
import secrets
import subprocess

CPP_PATH = "/home/user/mc_sim.cpp"
EXE_PATH = "/home/user/mc_sim"
REPORT_PATH = "/home/user/report.txt"
EXPECTED_VALUE = str(int(8000 * 8000 * 0.5 * 10))


def test_report_content():
    assert os.path.isfile(REPORT_PATH), f"File {REPORT_PATH} does not exist."

    with open(REPORT_PATH, "r") as f:
        content = f.read().strip()

    assert EXPECTED_VALUE in content, f"Expected value {EXPECTED_VALUE} not found in {REPORT_PATH}."


def test_executable_exists():
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."


def test_mc_sim_cpp_fixed():
    assert os.path.isfile(CPP_PATH), f"File {CPP_PATH} does not exist."

    with open(CPP_PATH, "r") as f:
        content = f.read()

    # Extract the calculate_energy function body
    match = re.search(r'double\s+calculate_energy\s*\(\)\s*\{(.+?)return\s+sum;', content, re.DOTALL)
    assert match, "Could not find the calculate_energy function body."

    func_body = match.group(1)

    # Find the order of loops
    i_pos = func_body.find('for (int i')
    if i_pos == -1:
        i_pos = func_body.find('for(int i')

    j_pos = func_body.find('for (int j')
    if j_pos == -1:
        j_pos = func_body.find('for(int j')

    assert i_pos != -1 and j_pos != -1, "Could not find both 'i' and 'j' loops in calculate_energy."

    # In row-major traversal for data[i][j], the outer loop should be 'i' and inner loop should be 'j'.
    # Or if access is data[j][i], outer is 'j' and inner is 'i'.
    # Let's check the access pattern.
    access_ij = func_body.find('data[i][j]') != -1
    access_ji = func_body.find('data[j][i]') != -1

    assert access_ij or access_ji, "Could not find array access data[i][j] or data[j][i]."

    if access_ij:
        assert i_pos < j_pos, "Loop 'i' should be the outer loop (appear before loop 'j') for data[i][j] access."
    if access_ji:
        assert j_pos < i_pos, "Loop 'j' should be the outer loop (appear before loop 'i') for data[j][i] access."


def _replace_main(source, replacement):
    match = re.search(r'\bint\s+main\s*\([^)]*\)\s*\{', source)
    assert match, "Could not locate main()."
    opening = source.find('{', match.start())
    depth = 0
    state = "code"
    i = opening
    while i < len(source):
        c = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""
        if state == "code":
            if c == '/' and nxt == '/':
                state = "line"
                i += 1
            elif c == '/' and nxt == '*':
                state = "block"
                i += 1
            elif c == '"':
                state = "string"
            elif c == "'":
                state = "char"
            elif c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    return source[:match.start()] + replacement + source[i + 1:]
        elif state == "line":
            if c == '\n':
                state = "code"
        elif state == "block":
            if c == '*' and nxt == '/':
                state = "code"
                i += 1
        elif state in ("string", "char"):
            quote = '"' if state == "string" else "'"
            if c == '\\':
                i += 1
            elif c == quote:
                state = "code"
        i += 1
    raise AssertionError("Could not find the end of main().")


def test_compiled_program_and_calculation():
    with open(CPP_PATH, "r") as f:
        source = f.read()

    # Recompile exactly as requested and require the submitted executable to be
    # the artifact produced from the submitted source with g++ -O3.
    rebuilt = "/tmp/mc_sim_rebuilt"
    result = subprocess.run(
        ["g++", "-O3", "-o", rebuilt, CPP_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Submitted source does not compile:\n{result.stderr}"
    assert filecmp.cmp(EXE_PATH, rebuilt, shallow=False), \
        "The submitted executable was not produced from the submitted source using g++ -O3."

    # Actually execute the submitted artifact and compare its output to both
    # the independently derived answer and the report.
    run = subprocess.run(
        [EXE_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=180
    )
    assert run.returncode == 0, f"Executable failed with code {run.returncode}:\n{run.stderr}"
    output = run.stdout.strip()
    assert re.fullmatch(r'-?\d+', output), f"Unexpected program output: {run.stdout!r}"
    assert output == EXPECTED_VALUE, f"Program produced {output}, expected {EXPECTED_VALUE}."
    with open(REPORT_PATH, "r") as f:
        report = f.read().strip()
    assert report == output, "report.txt does not contain exactly the program's numerical output."

    # Exercise calculate_energy itself on verifier-chosen, nonuniform matrices.
    n = 17 + secrets.randbelow(20)
    seeds = [secrets.randbelow(1000000) for _ in range(3)]
    varied_source, count = re.subn(
        r'const\s+int\s+N\s*=\s*8000\s*;',
        f'const int N = {n};', source, count=1
    )
    assert count == 1, "The required N declaration was unexpectedly changed."

    seed_list = ", ".join(str(x) for x in seeds)
    harness_main = f'''int main() {{
    const long long seeds[] = {{{seed_list}}};
    data.assign(N, std::vector<double>(N));
    for (int r = 0; r < 3; ++r) {{
        for (int i = 0; i < N; ++i) {{
            for (int j = 0; j < N; ++j) {{
                data[i][j] = (double)((seeds[r] + i * 17LL + j * 31LL + r * 13LL) % 101LL - 50LL);
            }}
        }}
        std::cout << (long long)calculate_energy() << std::endl;
    }}
    return 0;
}}'''
    varied_source = _replace_main(varied_source, harness_main)
    harness_cpp = "/tmp/mc_sim_harness.cpp"
    harness_exe = "/tmp/mc_sim_harness"
    with open(harness_cpp, "w") as f:
        f.write(varied_source)

    build = subprocess.run(
        ["g++", "-O3", "-o", harness_exe, harness_cpp],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
    )
    assert build.returncode == 0, f"Could not compile calculation harness:\n{build.stderr}"
    exercised = subprocess.run(
        [harness_exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=60
    )
    assert exercised.returncode == 0, f"Calculation harness failed:\n{exercised.stderr}"

    expected = []
    for r, seed in enumerate(seeds):
        total = sum(
            (seed + i * 17 + j * 31 + r * 13) % 101 - 50
            for i in range(n) for j in range(n)
        )
        expected.append(str(total))
    assert exercised.stdout.splitlines() == expected, \
        "calculate_energy did not correctly process verifier-chosen matrix contents."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
