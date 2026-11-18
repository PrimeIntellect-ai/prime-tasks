#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import stat
import subprocess
import tempfile

HOME = "/home/user"
SOURCE = f"{HOME}/mc_sphere.c"
SCRIPT = f"{HOME}/run_experiment.sh"


def expected_line(n):
    seed = 42
    inside = 0
    for _ in range(n):
        coords = []
        for _ in range(3):
            seed = (1103515245 * seed + 12345) % 2147483648
            coords.append((seed / 2147483648.0) * 2.0 - 1.0)
        if coords[0] ** 2 + coords[1] ** 2 + coords[2] ** 2 < 1.0:
            inside += 1
    volume = 8.0 * inside / n
    error = abs(volume - 4.188790204786)
    return f"{n} {error:.6f}"


def get_expected_results():
    results = []
    plot_lines = []
    for n in range(10000, 100001, 10000):
        line = expected_line(n)
        results.append(line)
        error = float(line.split()[1])
        plot_lines.append(f"{n:>6} | " + "*" * int(math.floor(error * 500)))
    return "\n".join(results) + "\n", "\n".join(plot_lines) + "\n"


def uncommented_source():
    with open(SOURCE, encoding="utf-8") as f:
        text = f.read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def test_files_exist():
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} does not exist."


def test_script_executable():
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"{SCRIPT} is not executable."


def test_c_source_structure_and_behavior():
    source = uncommented_source()
    assert source.strip(), "mc_sphere.c is empty."

    includes = re.findall(r'^\s*#\s*include\s*[<\"]([^>\"]+)[>\"]', source, flags=re.M)
    allowed = {"stdio.h", "stdlib.h", "math.h"}
    assert set(includes) <= allowed, f"Only the requested standard headers may be used; found {includes}."

    assert re.search(r"\bunsigned\s+long\s+long\s+seed\s*=\s*42(?:[uUlL]*)\s*;", source), \
        "The required unsigned long long seed initialized to 42 is missing."
    for constant in ("1103515245", "12345", "2147483648"):
        assert constant in source, f"The required LCG constant {constant} is missing."
    assert re.search(r"seed\s*=.*1103515245.*seed.*12345.*%\s*2147483648", source), \
        "The required LCG update of seed is missing."

    has_dynamic_array = bool(re.search(r"\b(?:malloc|calloc|realloc)\s*\(", source))
    has_declared_array = bool(re.search(
        r"\b(?:double|float)\s+[A-Za-z_]\w*\s*\[[^\]]+\](?:\s*\[[^\]]+\])?", source
    ))
    assert has_dynamic_array or has_declared_array, \
        "No allocated coordinate array (dynamic or VLA/array declaration) was found."
    assert len(re.findall(r"\b(?:for|while)\s*\(", source)) >= 2, \
        "The source must generate/store coordinates and then iterate through the array."

    binary = "/tmp/mc_sphere_behavior_test"
    build = subprocess.run(
        ["/usr/bin/gcc", "-std=c11", "-O3", SOURCE, "-lm", "-o", binary],
        capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"mc_sphere.c did not compile with -O3:\n{build.stderr}"

    # Exercise inputs outside the ten experiment values so a fixed-output stub cannot pass.
    for n in (1, 2, 7, 31, 123, 999, 12345, 54321):
        run = subprocess.run([binary, str(n)], capture_output=True, text=True, timeout=15)
        assert run.returncode == 0, f"mc_sphere failed for N={n}: {run.stderr}"
        assert run.stdout == expected_line(n) + "\n", \
            f"Incorrect simulator output for N={n}. Expected {expected_line(n)!r}, got {run.stdout!r}."


def make_tool_wrappers(directory, compile_log, run_log, awk_log):
    gcc_wrapper = f'''#!/bin/bash
real=/usr/bin/gcc
has_source=0
has_o3=0
out=a.out
previous=""
for arg in "$@"; do
    case "$arg" in
        mc_sphere.c|*/mc_sphere.c) has_source=1 ;;
        -O3) has_o3=1 ;;
        -o*) if [ "$arg" != "-o" ]; then out="${{arg#-o}}"; fi ;;
    esac
    if [ "$previous" = "-o" ]; then out="$arg"; fi
    previous="$arg"
done
"$real" "$@"
status=$?
if [ $status -ne 0 ]; then exit $status; fi
if [ $has_source -eq 1 ] && [ $has_o3 -eq 1 ] && [ -x "$out" ]; then
    realout="$(readlink -f "$out").__verifier_real"
    mv -f "$out" "$realout"
    cat > "$out" <<WRAP_EOF
#!/bin/bash
printf '%s\\n' "\$1" >> '{run_log}'
exec '$realout' "\$@"
WRAP_EOF
    chmod +x "$out"
    printf 'COMPILED\\t%s\\n' "$out" >> '{compile_log}'
fi
exit 0
'''
    with open(os.path.join(directory, "gcc"), "w") as f:
        f.write(gcc_wrapper)
    os.chmod(os.path.join(directory, "gcc"), 0o755)

    for name, real in (("awk", "/usr/bin/awk"), ("gawk", "/usr/bin/gawk")):
        wrapper = f'''#!/bin/bash
printf 'USED\\n' >> '{awk_log}'
exec '{real}' "$@"
'''
        path = os.path.join(directory, name)
        with open(path, "w") as f:
            f.write(wrapper)
        os.chmod(path, 0o755)


def test_experiment_results():
    for path in (f"{HOME}/mc_errors.txt", f"{HOME}/error_plot.txt", f"{HOME}/mc_sphere"):
        if os.path.exists(path):
            os.remove(path)

    with open(SCRIPT, encoding="utf-8") as f:
        script_source = f.read()
    assert re.search(r"\b(?:awk|gawk)\b", script_source), \
        "run_experiment.sh must use awk to generate the plot."

    with tempfile.TemporaryDirectory() as tool_dir:
        compile_log = os.path.join(tool_dir, "compile.log")
        run_log = os.path.join(tool_dir, "run.log")
        awk_log = os.path.join(tool_dir, "awk.log")
        make_tool_wrappers(tool_dir, compile_log, run_log, awk_log)

        env = os.environ.copy()
        env["PATH"] = tool_dir + os.pathsep + env.get("PATH", "")
        result = subprocess.run(
            [SCRIPT], cwd=HOME, env=env, capture_output=True, text=True, timeout=90
        )
        assert result.returncode == 0, \
            f"run_experiment.sh failed with return code {result.returncode}.\nStderr: {result.stderr}"

        assert os.path.isfile(compile_log), \
            "The script did not compile mc_sphere.c with gcc and -O3."
        with open(compile_log) as f:
            compiled_outputs = [line.rstrip("\n").split("\t", 1)[1] for line in f if "\t" in line]
        assert any(os.path.basename(path) == "mc_sphere" for path in compiled_outputs), \
            "The script did not compile mc_sphere.c into an executable named mc_sphere."
        assert os.path.isfile(f"{HOME}/mc_sphere") and os.access(f"{HOME}/mc_sphere", os.X_OK), \
            "The mc_sphere executable was not created."

        assert os.path.isfile(run_log), "The experiment never ran the executable it compiled."
        with open(run_log) as f:
            observed = [line.strip() for line in f if line.strip()]
        required = [str(n) for n in range(10000, 100001, 10000)]
        position = 0
        for value in observed:
            if position < len(required) and value == required[position]:
                position += 1
        assert position == len(required), \
            f"The compiled simulator was not run for all required N values in order; observed {observed}."
        assert os.path.isfile(awk_log), "The script did not invoke awk to generate the plot."

    assert os.path.isfile(f"{HOME}/mc_errors.txt"), f"{HOME}/mc_errors.txt was not created."
    assert os.path.isfile(f"{HOME}/error_plot.txt"), f"{HOME}/error_plot.txt was not created."

    with open(f"{HOME}/mc_errors.txt") as f:
        mc_errors = f.read()
    with open(f"{HOME}/error_plot.txt") as f:
        error_plot = f.read()

    expected_errors, expected_plot = get_expected_results()
    assert mc_errors.strip() == expected_errors.strip(), \
        f"Contents of mc_errors.txt do not match expected results.\nExpected:\n{expected_errors}\nGot:\n{mc_errors}"
    assert error_plot.rstrip() == expected_plot.rstrip(), \
        f"Contents of error_plot.txt do not match expected results.\nExpected:\n{expected_plot}\nGot:\n{error_plot}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
