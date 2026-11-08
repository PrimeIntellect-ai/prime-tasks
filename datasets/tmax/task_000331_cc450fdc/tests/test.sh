#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import secrets
import shutil
import subprocess
import tempfile

LIB = "/home/user/libmathapi.so"
HARNESS_SRC = "/home/user/test_harness.c"
HARNESS = "/home/user/test_harness"
GENERATOR = "/home/user/generate_urls.sh"
LOG = "/home/user/sorted_results.log"

EXPECTED_URLS = []
for i in range(1, 11):
    EXPECTED_URLS.extend([
        f"/api/add?a={i}&b={i * 2}",
        f"/api/add?a={i * 2}&b={i}",
    ])

EXPECTED_LINES = sorted([
    f"{url} = {int(url.split('a=')[1].split('&')[0]) + int(url.split('b=')[1])}.00"
    for url in EXPECTED_URLS
])


def run(cmd, *, input_text=None, env=None):
    return subprocess.run(
        cmd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        env=env,
        check=False,
    )


def harness_env():
    env = os.environ.copy()
    old = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = "/home/user" + ((":" + old) if old else "")
    return env


def expected_harness_output(urls):
    result = []
    for url in urls:
        if url == "/not-an-api-url":
            result.append(f"{url} = ERROR")
        else:
            a = int(url.split("a=")[1].split("&")[0])
            b = int(url.split("b=")[1])
            result.append(f"{url} = {a + b:.2f}")
    return result


def test_shared_library_exists():
    assert os.path.isfile(LIB), f"Shared library missing: {LIB}"
    assert os.access(LIB, os.R_OK), f"Shared library not readable: {LIB}"
    with open(LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Shared library is not an ELF file: {LIB}"


def test_shared_library_is_loadable_and_works():
    lib = ctypes.CDLL(LIB)
    evaluate = lib.evaluate_url
    evaluate.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_double)]
    evaluate.restype = ctypes.c_int

    for _ in range(6):
        a = secrets.randbelow(9000) + 1000
        b = secrets.randbelow(9000) + 1000
        out = ctypes.c_double()
        url = f"/api/add?a={a}&b={b}".encode()
        assert evaluate(url, ctypes.byref(out)) == 0
        assert out.value == float(a + b)

    out = ctypes.c_double()
    assert evaluate(b"/not-an-api-url", ctypes.byref(out)) != 0


def test_test_harness_c_exists():
    assert os.path.isfile(HARNESS_SRC), f"Test harness source missing: {HARNESS_SRC}"


def test_test_harness_executable_exists():
    assert os.path.isfile(HARNESS), f"Test harness executable missing: {HARNESS}"
    assert os.access(HARNESS, os.X_OK), f"Test harness is not executable: {HARNESS}"
    with open(HARNESS, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Test harness is not a compiled ELF executable: {HARNESS}"


def test_generate_urls_script_exists():
    assert os.path.isfile(GENERATOR), f"Generate URLs script missing: {GENERATOR}"
    assert os.access(GENERATOR, os.X_OK), f"Generate URLs script is not executable: {GENERATOR}"


def test_generator_and_harness_execution():
    generated = run([GENERATOR])
    assert generated.returncode == 0, generated.stderr
    generated_lines = generated.stdout.splitlines()
    assert generated_lines == EXPECTED_URLS, (
        "generate_urls.sh must emit exactly the specified 20 URLs in pair order"
    )

    random_urls = []
    for _ in range(7):
        a = secrets.randbelow(900000) + 10000
        b = secrets.randbelow(900000) + 10000
        random_urls.append(f"/api/add?a={a}&b={b}")
    random_urls.append("/not-an-api-url")
    input_text = "\n".join(random_urls) + "\n"
    expected = expected_harness_output(random_urls)

    executed = run([HARNESS], input_text=input_text, env=harness_env())
    assert executed.returncode == 0, executed.stderr
    assert executed.stdout.splitlines() == expected

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "rebuilt_harness")
        compiled = run([
            "gcc", HARNESS_SRC, "-o", rebuilt,
            "-L/home/user", "-lmathapi", "-ldl", "-lm"
        ])
        assert compiled.returncode == 0, (
            "test_harness.c could not be compiled against libmathapi.so:\n" + compiled.stderr
        )
        rebuilt_run = run([rebuilt], input_text=input_text, env=harness_env())
        assert rebuilt_run.returncode == 0, rebuilt_run.stderr
        assert rebuilt_run.stdout.splitlines() == expected

        probe_c = os.path.join(td, "probe.c")
        probe_so = os.path.join(td, "libmathapi.so")
        with open(probe_c, "w") as f:
            f.write(
                "int evaluate_url(const char *url, double *out_val) {"
                "(void)url; *out_val = 1234.5; return 0; }\n"
            )
        probe_build = run(["gcc", "-shared", "-fPIC", probe_c, "-o", probe_so])
        assert probe_build.returncode == 0, probe_build.stderr

        backup = os.path.join(td, "original-libmathapi.so")
        shutil.copy2(LIB, backup)
        try:
            os.replace(probe_so, LIB)
            probe_url = f"/api/add?a={secrets.randbelow(1000)}&b={secrets.randbelow(1000)}"
            probe_input = probe_url + "\n"
            probe_expected = f"{probe_url} = 1234.50"
            for executable in (HARNESS, rebuilt):
                probed = run([executable], input_text=probe_input, env=harness_env())
                assert probed.returncode == 0, probed.stderr
                assert probed.stdout.splitlines() == [probe_expected], (
                    f"{executable} does not actively call evaluate_url from libmathapi.so"
                )
        finally:
            os.replace(backup, LIB)


def test_sorted_results_log():
    assert os.path.isfile(LOG), f"Sorted results log missing: {LOG}"

    with open(LOG, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == 20, f"Expected exactly 20 lines in {LOG}, found {len(actual_lines)}"
    assert set(actual_lines) == set(EXPECTED_LINES), (
        "The generated results do not match the expected output values."
    )
    assert actual_lines == EXPECTED_LINES, (
        f"The lines in {LOG} are not sorted correctly according to bytewise alphabetical order."
    )

    generated = run([GENERATOR])
    assert generated.returncode == 0, generated.stderr
    evaluated = run([HARNESS], input_text=generated.stdout, env=harness_env())
    assert evaluated.returncode == 0, evaluated.stderr
    runtime_sorted = sorted(evaluated.stdout.splitlines())
    assert runtime_sorted == actual_lines, (
        "sorted_results.log does not match the sorted output produced by the submitted generator and harness"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
