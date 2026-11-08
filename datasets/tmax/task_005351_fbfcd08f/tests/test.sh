#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import math
import os
import re
import shutil
import stat
import subprocess
import tempfile

SOURCE = "/home/user/compute_jsd.c"
EXE = "/home/user/compute_jsd"
OUTPUT = "/home/user/jsd_output.txt"
PROFILE = "/home/user/profile.sh"
TIMES = "/home/user/times.txt"

ORIGINAL = r'''#include <stdio.h>
#include <math.h>

double P(double x) {
    return exp(-x*x);
}

double Q(double x) {
    return exp(-(x-1.0)*(x-1.0));
}

int main() {
    long long N = 50000000;
    double a = -10.0;
    double b = 10.0;
    double dx = (b - a) / N;

    double sum_P = 0.5 * (P(a) + P(b));
    double sum_Q = 0.5 * (Q(a) + Q(b));

    for(long long i = 1; i < N; i++) {
        double x = a + i * dx;
        sum_P += P(x);
        sum_Q += Q(x);
    }

    sum_P *= dx;
    sum_Q *= dx;

    double sum_JSD = 0.0;
    for(long long i = 1; i < N; i++) {
        double x = a + i * dx;
        double p = P(x) / sum_P;
        double q = Q(x) / sum_Q;
        double m = 0.5 * (p + q);
        if (p > 0) sum_JSD += 0.5 * p * log(p / m);
        if (q > 0) sum_JSD += 0.5 * q * log(q / m);
    }

    double p_a = P(a)/sum_P, q_a = Q(a)/sum_Q, m_a = 0.5*(p_a+q_a);
    double p_b = P(b)/sum_P, q_b = Q(b)/sum_Q, m_b = 0.5*(p_b+q_b);
    double end_JSD = 0.0;
    if (p_a > 0) end_JSD += 0.5 * p_a * log(p_a / m_a);
    if (q_a > 0) end_JSD += 0.5 * q_a * log(q_a / m_a);
    if (p_b > 0) end_JSD += 0.5 * p_b * log(p_b / m_b);
    if (q_b > 0) end_JSD += 0.5 * q_b * log(q_b / m_b);

    sum_JSD += 0.5 * end_JSD;
    sum_JSD *= dx;

    printf("%.6f\n", sum_JSD);
    return 0;
}
'''

PRAGMA_LINE = re.compile(r'(?m)^[ \t]*#[ \t]*pragma[ \t]+omp[ \t]+parallel[ \t]+for[ \t]+reduction[ \t]*\([ \t]*\+[ \t]*:[ \t]*([A-Za-z_][A-Za-z0-9_]*(?:[ \t]*,[ \t]*[A-Za-z_][A-Za-z0-9_]*)*)[ \t]*\)[ \t]*$')

def without_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)

def tokens(text):
    text = without_comments(text)
    return re.findall(r'[A-Za-z_]\w*|(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?|==|!=|<=|>=|\+\+|--|&&|\|\||.', text, flags=re.S)

def run_number(path, threads="4"):
    env = os.environ.copy()
    env["OMP_NUM_THREADS"] = threads
    proc = subprocess.run([path], cwd="/home/user", env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=120, check=True)
    lines = proc.stdout.strip().splitlines()
    assert len(lines) == 1, f"{path} must print exactly one output line"
    assert re.fullmatch(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?', lines[0]), \
        f"{path} did not print a single floating-point number: {proc.stdout!r}"
    return float(lines[0]), lines[0]

def test_final_state():
    # Source must retain the supplied mathematics and contain two active,
    # correctly placed reductions—one for each original integration loop.
    assert os.path.exists(SOURCE), f"{SOURCE} is missing."
    content = open(SOURCE).read()
    matches = list(PRAGMA_LINE.finditer(content))
    assert len(matches) == 2, "Expected exactly two active OpenMP parallel-for reduction pragmas."
    assert set(x.strip() for x in matches[0].group(1).split(',')) == {"sum_P", "sum_Q"}, \
        "The first integration loop must reduce sum_P and sum_Q."
    assert set(x.strip() for x in matches[1].group(1).split(',')) == {"sum_JSD"}, \
        "The second integration loop must reduce sum_JSD."
    for match in matches:
        following = without_comments(content[match.end():]).lstrip()
        assert re.match(r'for\s*\(', following), "Each OpenMP pragma must immediately precede a for loop."
    stripped = PRAGMA_LINE.sub('', content)
    assert tokens(stripped) == tokens(ORIGINAL), \
        "The program's mathematical logic or grid size was changed; only the OpenMP pragmas may be added."

    # Preserve the original executable checks, and ensure it is a real OpenMP ELF
    # program whose behavior agrees with a fresh -O3/-fopenmp/-lm build.
    assert os.path.exists(EXE), f"{EXE} executable is missing."
    assert os.access(EXE, os.X_OK), f"{EXE} is not executable."
    with open(EXE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{EXE} is not a compiled ELF executable."
    linked = subprocess.run(['ldd', EXE], text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=20, check=True).stdout
    assert 'libgomp' in linked, "The executable is not linked with the OpenMP runtime (-fopenmp)."
    assert 'libm.so' in linked, "The executable is not linked with the math library (-lm)."

    with tempfile.TemporaryDirectory() as td:
        reference = os.path.join(td, 'compute_jsd_reference')
        subprocess.run(['gcc', '-O3', '-fopenmp', SOURCE, '-lm', '-o', reference],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                       timeout=120, check=True)
        expected, expected_text = run_number(reference)
        actual, actual_text = run_number(EXE)
    assert math.isfinite(actual) and abs(actual - expected) <= 5e-7, \
        f"Executable result {actual_text} disagrees with the compiled source result {expected_text}."

    # Retain the exact output-file assertion and also tie it to executable behavior.
    assert os.path.exists(OUTPUT), f"{OUTPUT} is missing."
    saved_output = open(OUTPUT).read().strip()
    assert saved_output == "0.113271", f"Expected JSD output 0.113271, got {saved_output!r}"
    assert saved_output == actual_text, "jsd_output.txt is not the output produced by the executable."

    # Preserve profile-script checks and require the specified command to be present.
    assert os.path.exists(PROFILE), f"{PROFILE} is missing."
    assert os.access(PROFILE, os.X_OK), f"{PROFILE} is not executable."
    profile_text = open(PROFILE).read()
    assert re.search(r'/usr/bin/time\s+-f\s+[\"\']%e[\"\']\s+\./compute_jsd(?:\s|$)', profile_text), \
        "profile.sh must use /usr/bin/time -f \"%e\" ./compute_jsd."

    # Exercise profile.sh with instrumented stand-ins. This verifies exactly three
    # sequential executable invocations, the exact /usr/bin/time arguments,
    # stdout disposal, and that time's stderr is appended as the three file lines.
    exe_backup = EXE + '.verifier-backup'
    time_path = '/usr/bin/time'
    time_backup = time_path + '.verifier-backup'
    calls = '/tmp/profile_time_calls'
    active = '/tmp/profile_compute_active'
    overlap = '/tmp/profile_compute_overlap'
    for p in (calls, overlap):
        try: os.unlink(p)
        except FileNotFoundError: pass
    try:
        os.rename(EXE, exe_backup)
        with open(EXE, 'w') as f:
            f.write('#!/bin/bash\n'
                    'if ! mkdir "' + active + '" 2>/dev/null; then echo overlap > "' + overlap + '"; exit 9; fi\n'
                    'sleep 0.15\n'
                    'rmdir "' + active + '"\n'
                    'echo PROFILE_STDOUT_MUST_BE_DISCARDED\n')
        os.chmod(EXE, 0o755)

        os.rename(time_path, time_backup)
        with open(time_path, 'w') as f:
            f.write('#!/bin/bash\n'
                    'printf "%s\\t%s\\t%s\\n" "$1" "$2" "$3" >> "' + calls + '"\n'
                    '[ "$#" -eq 3 ] && [ "$1" = "-f" ] && [ "$2" = "%e" ] && [ "$3" = "./compute_jsd" ] || exit 8\n'
                    '"$3"\n'
                    'rc=$?\n'
                    'n=$(wc -l < "' + calls + '")\n'
                    'case "$n" in 1) echo 731.101 >&2;; 2) echo 731.202 >&2;; 3) echo 731.303 >&2;; *) echo 731.999 >&2;; esac\n'
                    'exit "$rc"\n')
        os.chmod(time_path, 0o755)

        try: os.unlink(TIMES)
        except FileNotFoundError: pass
        proc = subprocess.run([PROFILE], cwd='/home/user', text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              timeout=30)
        assert proc.returncode == 0, f"profile.sh failed: stdout={proc.stdout!r}, stderr={proc.stderr!r}"
        assert 'PROFILE_STDOUT_MUST_BE_DISCARDED' not in proc.stdout, \
            "profile.sh did not discard compute_jsd standard output."
        assert not os.path.exists(overlap), "The three profile executions were not sequential."
        call_lines = open(calls).read().splitlines() if os.path.exists(calls) else []
        assert call_lines == ['-f\t%e\t./compute_jsd'] * 3, \
            "profile.sh must invoke the specified system time command exactly three times."
    finally:
        if os.path.exists(time_backup):
            try: os.unlink(time_path)
            except FileNotFoundError: pass
            os.rename(time_backup, time_path)
        if os.path.exists(exe_backup):
            try: os.unlink(EXE)
            except FileNotFoundError: pass
            os.rename(exe_backup, EXE)
        try: shutil.rmtree(active)
        except FileNotFoundError: pass

    # Retain and strengthen the original times.txt assertions.
    assert os.path.exists(TIMES), f"{TIMES} is missing."
    lines = open(TIMES).read().strip().split('\n')
    assert len(lines) == 3, f"{TIMES} should contain exactly 3 lines, found {len(lines)}."
    values = []
    for i, line in enumerate(lines):
        try:
            value = float(line)
        except ValueError:
            raise AssertionError(f"Line {i+1} in {TIMES} is not a valid floating-point number: {line!r}")
        assert math.isfinite(value) and value >= 0
        values.append(line)
    assert values == ['731.101', '731.202', '731.303'], \
        "times.txt was not populated from the three measured profile runs."
PY

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
