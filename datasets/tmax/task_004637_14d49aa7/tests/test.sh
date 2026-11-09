#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import subprocess

PIPELINE_DIR = "/home/user/pipeline"
CALC_C = os.path.join(PIPELINE_DIR, "calc.c")
MAKEFILE = os.path.join(PIPELINE_DIR, "Makefile")
CI_TEST_SH = os.path.join(PIPELINE_DIR, "ci_test.sh")
CI_REPORT_TXT = os.path.join(PIPELINE_DIR, "ci_report.txt")
TESTS_TXT = os.path.join(PIPELINE_DIR, "tests.txt")


def run(command, **kwargs):
    return subprocess.run(command, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def test_makefile_contains_debug_symbols():
    assert os.path.isfile(MAKEFILE), f"Makefile not found at {MAKEFILE}"
    with open(MAKEFILE, "r") as f:
        content = f.read()
    assert "-g" in content, "Makefile does not contain the '-g' flag for debugging symbols."


def test_ci_test_sh_exists():
    assert os.path.isfile(CI_TEST_SH), f"Test orchestration script not found at {CI_TEST_SH}"
    syntax = run(["bash", "-n", CI_TEST_SH])
    assert syntax.returncode == 0, f"ci_test.sh is not valid Bash:\n{syntax.stderr}"


def test_ci_report_contents():
    assert os.path.isfile(CI_REPORT_TXT), f"Report file not found at {CI_REPORT_TXT}"

    expected_lines = [
        "[1] result=15 status=PASS",
        "[3] result=11 status=PASS",
        "[5] result=50 status=PASS"
    ]

    with open(CI_REPORT_TXT, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {CI_REPORT_TXT} do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_calc_c_fixed():
    assert os.path.isfile(CALC_C), f"calc.c not found at {CALC_C}"
    with open(CALC_C, "r") as f:
        content = f.read()
    assert "free(" in content, "calc.c does not seem to contain a call to free() to fix the memory leak."


def test_rebuilt_calc_has_debug_info_and_no_real_leak():
    if os.path.exists(os.path.join(PIPELINE_DIR, "calc")):
        os.unlink(os.path.join(PIPELINE_DIR, "calc"))

    built = run(["make"], cwd=PIPELINE_DIR)
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"

    calc = os.path.join(PIPELINE_DIR, "calc")
    assert os.path.isfile(calc) and os.access(calc, os.X_OK), "make did not produce an executable calc"

    sections = run(["readelf", "-S", calc])
    assert sections.returncode == 0 and ".debug_info" in sections.stdout, \
        "The rebuilt calc binary does not contain debugging information"

    for a, b, op, expected in [(10, 5, "+", 15), (15, 4, "-", 11), (7, 6, "*", 42)]:
        checked = run([
            "/usr/bin/valgrind", "--leak-check=full",
            "--errors-for-leak-kinds=definite", "--error-exitcode=99",
            calc, str(a), str(b), op
        ], cwd=PIPELINE_DIR)
        assert checked.returncode == 0, (
            f"calc failed Valgrind for {a} {b} {op}:\n{checked.stderr}"
        )
        assert checked.stdout.strip() == str(expected)
        assert "definitely lost: 0 bytes" in checked.stderr, \
            f"Valgrind did not report zero definitely-lost bytes:\n{checked.stderr}"


def test_ci_script_rebuilds_runs_valgrind_and_handles_generated_cases():
    rng = random.SystemRandom()
    base_id = rng.randrange(10000, 90000)
    fake_leak_a = -rng.randrange(6000, 9000)
    plus_a, plus_b = rng.randrange(1, 20), rng.randrange(1, 20)
    skip_a, skip_b = rng.randrange(8, 15), rng.randrange(8, 15)
    minus_a, minus_b = rng.randrange(-20, 10), rng.randrange(10, 30)

    cases = [
        (base_id, plus_a, plus_b, "+", plus_a + plus_b, "PASS"),
        (base_id + 1, skip_a, skip_b, "*", skip_a * skip_b, None),
        (base_id + 2, fake_leak_a, 3, "+", fake_leak_a + 3, "LEAK"),
        (base_id + 3, minus_a, minus_b, "-", minus_a - minus_b, "PASS"),
        (base_id + 4, 10, 5, "*", 50, "PASS"),
    ]
    assert cases[1][4] > 50

    with open(TESTS_TXT, "r") as f:
        old_tests = f.read()

    make_path = shutil.which("make")
    valgrind_path = shutil.which("valgrind")
    assert make_path and valgrind_path
    make_real = make_path + ".verifier-real"
    valgrind_real = valgrind_path + ".verifier-real"
    make_log = "/tmp/verifier_make_calls.log"
    valgrind_log = "/tmp/verifier_valgrind_calls.log"

    for log in (make_log, valgrind_log):
        with open(log, "w"):
            pass
        os.chmod(log, 0o666)

    make_wrapper = f'''#!/bin/bash
echo called >> {make_log}
exec {make_real} "$@"
'''
    valgrind_wrapper = f'''#!/bin/bash
echo called >> {valgrind_log}
args=("$@")
for ((i=0; i<${{#args[@]}}; i++)); do
    if [[ "${{args[i]}}" == "${{VERIFIER_FAKE_LEAK_A:-}}" ]]; then
        for ((j=0; j<${{#args[@]}}; j++)); do
            if [[ "${{args[j]}}" == */calc || "${{args[j]}}" == calc || "${{args[j]}}" == ./calc ]]; then
                "${{args[@]:j}}"
                rc=$?
                echo "definitely lost: 7 bytes in 1 blocks" >&2
                exit $rc
            fi
        done
    fi
done
exec {valgrind_real} "$@"
'''

    installed = []
    try:
        with open(TESTS_TXT, "w") as f:
            for case_id, a, b, op, _, _ in cases:
                f.write(f"{case_id},{a},{b},{op}\n")

        for path, real, wrapper in (
            (make_path, make_real, make_wrapper),
            (valgrind_path, valgrind_real, valgrind_wrapper),
        ):
            assert not os.path.exists(real), f"Temporary verifier path already exists: {real}"
            os.rename(path, real)
            installed.append((path, real))
            with open(path, "w") as f:
                f.write(wrapper)
            os.chmod(path, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                           stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        calc = os.path.join(PIPELINE_DIR, "calc")
        if os.path.exists(calc):
            os.unlink(calc)

        env = os.environ.copy()
        env["VERIFIER_FAKE_LEAK_A"] = str(fake_leak_a)
        executed = run(
            ["runuser", "-u", "user", "--", "env",
             f"VERIFIER_FAKE_LEAK_A={fake_leak_a}", "bash", CI_TEST_SH],
            cwd=PIPELINE_DIR, env=env, timeout=120
        )
        assert executed.returncode == 0, (
            f"ci_test.sh failed:\nstdout:\n{executed.stdout}\nstderr:\n{executed.stderr}"
        )
        assert os.path.isfile(calc) and os.access(calc, os.X_OK), \
            "ci_test.sh did not recreate the calc binary"

        with open(make_log, "r") as f:
            make_calls = len([line for line in f if line.strip()])
        with open(valgrind_log, "r") as f:
            valgrind_calls = len([line for line in f if line.strip()])
        assert make_calls >= 1, "ci_test.sh did not invoke make"
        assert valgrind_calls >= len(cases), \
            "ci_test.sh did not invoke Valgrind for every generated test case"

        expected = [
            f"[{case_id}] result={result} status={status}"
            for case_id, _, _, _, result, status in cases if status is not None
        ]
        assert os.path.isfile(CI_REPORT_TXT), "ci_test.sh did not create ci_report.txt"
        with open(CI_REPORT_TXT, "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, (
            "ci_test.sh produced an incorrect report for generated inputs.\n"
            f"Expected: {expected}\nActual: {actual}"
        )
    finally:
        with open(TESTS_TXT, "w") as f:
            f.write(old_tests)
        for path, real in reversed(installed):
            try:
                if os.path.lexists(path):
                    os.unlink(path)
            finally:
                if os.path.exists(real):
                    os.rename(real, path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
