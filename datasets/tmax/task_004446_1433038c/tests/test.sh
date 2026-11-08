#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import os
import random
import subprocess

PIPELINE_DIR = "/home/user/pipeline"
C_FILE = os.path.join(PIPELINE_DIR, "fast_counter.c")
SETUP_FILE = os.path.join(PIPELINE_DIR, "setup.py")
PROCESS_FILE = os.path.join(PIPELINE_DIR, "process.py")
OUTPUT_FILE = os.path.join(PIPELINE_DIR, "output.log")
VENV_DIR = "/home/user/venv"
PYTHON_BIN = os.path.join(VENV_DIR, "bin", "python")
EXPECTED_OUTPUT = "Migration successful! Total words processed: 15"
EXPECTED_PROCESS = b'''import word_counter

data = [
    "Hello world",
    "This is a migration test for Python 3",
    "   Multiple    spaces   should be   handled  ",
    ""
]

total_words = 0
for line in data:
    total_words += word_counter.count_words(line)

print(f"Migration successful! Total words processed: {total_words}")
'''


def clean_env():
    env = os.environ.copy()
    env.pop("PYTHONPATH", None)
    env["PYTHONNOUSERSITE"] = "1"
    env["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
    return env


def expected_count(value):
    count = 0
    in_word = False
    for char in value:
        if char in " \t\n":
            in_word = False
        elif not in_word:
            count += 1
            in_word = True
    return count


def exercise_extension(cases, pipeline_first=False):
    probe = r'''
import json
import os
import sys
if sys.argv[1] == "pipeline":
    sys.path.insert(0, "/home/user/pipeline")
import word_counter
cases = json.load(sys.stdin)
results = []
for value in cases:
    result = word_counter.count_words(value)
    results.append({"value": result, "type": type(result).__name__})
errors = []
for args in [(), (123,)]:
    try:
        word_counter.count_words(*args)
    except TypeError:
        errors.append(True)
    else:
        errors.append(False)
print(json.dumps({"module_file": os.path.realpath(word_counter.__file__), "results": results, "errors": errors}))
'''
    mode = "pipeline" if pipeline_first else "installed"
    completed = subprocess.run(
        [PYTHON_BIN, "-c", probe, mode],
        input=json.dumps(cases),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd="/tmp",
        env=clean_env(),
        timeout=30,
    )
    assert completed.returncode == 0, completed.stderr
    try:
        report = json.loads(completed.stdout)
    except Exception as exc:
        raise AssertionError(f"Extension probe produced invalid output: {completed.stdout!r}; stderr={completed.stderr!r}") from exc

    module_file = report["module_file"]
    assert module_file.endswith(tuple(importlib.machinery.EXTENSION_SUFFIXES)), \
        f"word_counter is not a compiled extension: {module_file}"
    assert report["errors"] == [True, True], "count_words must reject missing and non-string arguments"
    assert [item["type"] for item in report["results"]] == ["int"] * len(cases), \
        "count_words must return Python 3 int objects"
    assert [item["value"] for item in report["results"]] == [expected_count(case) for case in cases]
    return module_file


def test_process_py_was_not_modified():
    assert os.path.isfile(PROCESS_FILE), f"File {PROCESS_FILE} does not exist."
    with open(PROCESS_FILE, "rb") as f:
        assert f.read() == EXPECTED_PROCESS, "process.py was modified"


def test_c_file_updated_for_python3():
    assert os.path.isfile(C_FILE), f"File {C_FILE} does not exist."
    with open(C_FILE, "r") as f:
        content = f.read()

    # Keep the original source-level assertions.
    assert "PyInt_FromLong" not in content, "Legacy PyInt_FromLong is still in fast_counter.c"
    assert "Py_InitModule" not in content, "Legacy Py_InitModule is still in fast_counter.c"
    assert "PyLong_FromLong" in content, "fast_counter.c does not use PyLong_FromLong"
    assert "PyModuleDef" in content, "fast_counter.c does not define a PyModuleDef struct"
    assert "PyInit_word_counter" in content, "fast_counter.c does not have PyInit_word_counter initialization function"


def test_setup_py_exists():
    assert os.path.isfile(SETUP_FILE), f"File {SETUP_FILE} does not exist. You need to create it to build the extension."


def test_venv_exists():
    assert os.path.isdir(VENV_DIR), f"Virtual environment directory {VENV_DIR} does not exist."
    assert os.path.isfile(PYTHON_BIN), f"Python executable not found in virtual environment at {PYTHON_BIN}."


def test_setup_builds_installs_and_extension_works():
    built = subprocess.run(
        [PYTHON_BIN, "-m", "pip", "install", "--force-reinstall", "--no-deps", PIPELINE_DIR],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd="/tmp",
        env=clean_env(),
        timeout=120,
    )
    assert built.returncode == 0, f"setup.py could not build and install the extension:\n{built.stdout}"

    rng = random.SystemRandom()
    delimiters = [" ", "\t", "\n", "  ", "\t \n"]
    cases = ["", " ", "Hello world", "one\ttwo\nthree", "café 世界", "no_delimiters"]
    for _ in range(20):
        words = [f"w{rng.randrange(1 << 40):x}" for _ in range(rng.randrange(1, 15))]
        value = rng.choice(delimiters) if rng.choice([True, False]) else ""
        value += "".join(word + (rng.choice(delimiters) if i + 1 < len(words) else "") for i, word in enumerate(words))
        if rng.choice([True, False]):
            value += rng.choice(delimiters)
        cases.append(value)

    installed_module = exercise_extension(cases, pipeline_first=False)
    venv_real = os.path.realpath(VENV_DIR)
    assert os.path.commonpath([venv_real, installed_module]) == venv_real, \
        f"word_counter was not installed into the requested virtual environment: {installed_module}"

    # Also test the module process.py will resolve when its own directory is first on sys.path.
    exercise_extension(cases, pipeline_first=True)


def test_output_log_correct_and_reproducible():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist. Did you run process.py and redirect the output?"
    with open(OUTPUT_FILE, "r") as f:
        original_content = f.read().strip()
    assert EXPECTED_OUTPUT in original_content, \
        f"Output log does not contain the expected success message. Found: {original_content}"
    assert original_content == EXPECTED_OUTPUT, f"Unexpected content in output.log: {original_content!r}"

    with open(OUTPUT_FILE, "wb") as output:
        completed = subprocess.run(
            [PYTHON_BIN, PROCESS_FILE],
            stdout=output,
            stderr=subprocess.PIPE,
            cwd=PIPELINE_DIR,
            env=clean_env(),
            timeout=30,
        )
    assert completed.returncode == 0, completed.stderr.decode("utf-8", "replace")
    with open(OUTPUT_FILE, "r") as f:
        reproduced = f.read().strip()
    assert reproduced == EXPECTED_OUTPUT, f"Running process.py produced: {reproduced!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
