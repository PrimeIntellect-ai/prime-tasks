#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import re
import shutil
import string
import subprocess
import tempfile

import yaml

LIB_DIR = "/app/c-string-hasher"
LIB_PATH = os.path.join(LIB_DIR, "libhasher.so")
PROCESS_PATH = "/home/user/process.py"
CI_PATH = "/home/user/repo/.github/workflows/ci.yml"
ORACLE_PATH = "/opt/oracle/process_oracle.py"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 30)
    return subprocess.run(cmd, **kwargs)


def expected_hash(value):
    return "".join(chr(ord(c) ^ 0x2A) for c in value)


def test_libhasher_built_and_make_rebuilds_it():
    assert os.path.isfile(LIB_PATH), f"Expected shared library {LIB_PATH} to be built by make."

    clean = run(["make", "clean"], cwd=LIB_DIR, text=True)
    assert clean.returncode == 0, clean.stdout + clean.stderr
    assert not os.path.exists(LIB_PATH), "make clean did not remove libhasher.so"

    build = run(["make"], cwd=LIB_DIR, text=True)
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(LIB_PATH), "make did not produce libhasher.so"
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libhasher.so is not an ELF shared object"

    loaded = ctypes.CDLL(LIB_PATH)
    assert hasattr(loaded, "compute_hash")
    assert hasattr(loaded, "free_hash_result")


def test_headers_are_self_contained_and_no_longer_circular():
    headers = {name: open(os.path.join(LIB_DIR, name), encoding="utf-8").read()
               for name in ("hash.h", "util.h")}

    include_re = re.compile(r'^\s*#\s*include\s*[\"<]([^\">]+)[\">]', re.MULTILINE)
    edges = {name: [inc for inc in include_re.findall(text) if inc in headers]
             for name, text in headers.items()}

    def visit(node, active, done):
        assert node not in active, f"Circular header inclusion remains: {' -> '.join(active + [node])}"
        if node in done:
            return
        for child in edges[node]:
            visit(child, active + [node], done)
        done.add(node)

    done = set()
    for header in headers:
        visit(header, [], done)

    for header in headers:
        source = f'#include "{header}"\nint main(void) {{ return 0; }}\n'
        result = run(
            ["gcc", "-Wall", "-Wextra", "-Werror", "-I", LIB_DIR,
             "-x", "c", "-fsyntax-only", "-"],
            input=source, text=True,
        )
        assert result.returncode == 0, f"{header} is not self-contained:\n{result.stderr}"


def test_c_core_still_has_expected_behavior_and_frees_results():
    lib = ctypes.CDLL(LIB_PATH)
    lib.compute_hash.argtypes = [ctypes.c_char_p]
    lib.compute_hash.restype = ctypes.c_void_p
    lib.free_hash_result.argtypes = [ctypes.c_void_p]
    lib.free_hash_result.restype = None

    for value in ("test_string", "Alpha123", "VendoredPackage"):
        ptr = lib.compute_hash(value.encode("ascii"))
        assert ptr, "compute_hash returned NULL"
        try:
            assert ctypes.string_at(ptr).decode("ascii") == expected_hash(value)
        finally:
            lib.free_hash_result(ptr)


def test_process_py_exists_and_uses_ctypes_loader():
    assert os.path.isfile(PROCESS_PATH), f"Expected Python wrapper {PROCESS_PATH} to exist."
    source = open(PROCESS_PATH, encoding="utf-8").read()
    tree = ast.parse(source, PROCESS_PATH)

    ctypes_names = {"ctypes"}
    cdll_names = set()
    imported_ctypes = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "ctypes":
                    imported_ctypes = True
                    ctypes_names.add(alias.asname or "ctypes")
        elif isinstance(node, ast.ImportFrom) and node.module == "ctypes":
            imported_ctypes = True
            for alias in node.names:
                if alias.name == "CDLL":
                    cdll_names.add(alias.asname or alias.name)
    assert imported_ctypes, "process.py must import ctypes"

    loads_required_library = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        is_cdll = (
            isinstance(node.func, ast.Attribute)
            and node.func.attr == "CDLL"
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id in ctypes_names
        ) or (isinstance(node.func, ast.Name) and node.func.id in cdll_names)
        if is_cdll and node.args:
            arg = node.args[0]
            if isinstance(arg, ast.Constant) and arg.value == LIB_PATH:
                loads_required_library = True
    assert loads_required_library, f"process.py must load {LIB_PATH} with ctypes.CDLL"
    assert "compute_hash" in source, "process.py does not reference compute_hash"
    assert "free_hash_result" in source, "process.py does not reference free_hash_result"

    if os.path.isfile(ORACLE_PATH):
        assert open(PROCESS_PATH, "rb").read() != open(ORACLE_PATH, "rb").read(), \
            "process.py must not be a byte-identical copy of the reference implementation"


def test_wrapper_really_calls_both_c_functions():
    probe_c = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static void *last_result = NULL;
char *compute_hash(const char *input) {
    (void)input;
    const char *answer = "ffi-probe-result-7319";
    char *p = malloc(strlen(answer) + 1);
    if (!p) return NULL;
    strcpy(p, answer);
    last_result = p;
    FILE *f = fopen("/tmp/ffi_compute_called", "w");
    if (f) { fputs("called", f); fclose(f); }
    return p;
}
void free_hash_result(char *ptr) {
    FILE *f = fopen("/tmp/ffi_free_called", "w");
    if (f) { fputs(ptr == last_result ? "correct" : "wrong", f); fclose(f); }
    if (ptr == last_result) { free(ptr); last_result = NULL; }
}
'''
    for marker in ("/tmp/ffi_compute_called", "/tmp/ffi_free_called"):
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass

    with tempfile.TemporaryDirectory() as td:
        source_path = os.path.join(td, "probe.c")
        backup_path = os.path.join(td, "libhasher.original.so")
        with open(source_path, "w", encoding="utf-8") as f:
            f.write(probe_c)
        shutil.copy2(LIB_PATH, backup_path)
        try:
            built = run(["gcc", "-shared", "-fPIC", "-o", LIB_PATH, source_path], text=True)
            assert built.returncode == 0, built.stdout + built.stderr
            result = run(["python3", PROCESS_PATH, "input-not-known-to-wrapper"], text=False)
        finally:
            shutil.copy2(backup_path, LIB_PATH)

    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert result.stdout.strip() == b"ffi-probe-result-7319", \
        "process.py did not print the value returned by the C compute_hash function"
    assert os.path.isfile("/tmp/ffi_compute_called"), "C compute_hash was not called"
    assert os.path.isfile("/tmp/ffi_free_called"), "C free_hash_result was not called"
    assert open("/tmp/ffi_free_called", encoding="utf-8").read() == "correct", \
        "free_hash_result was not called with the pointer returned by compute_hash"


def test_wrapper_argument_count_and_fuzz_equivalence():
    missing = run(["python3", PROCESS_PATH], text=True)
    extra = run(["python3", PROCESS_PATH, "one", "two"], text=True)
    assert missing.returncode != 0, "process.py must reject a missing string argument"
    assert extra.returncode != 0, "process.py must accept exactly one string argument"

    random.seed(42)
    chars = string.ascii_letters + string.digits
    for _ in range(50):
        length = random.randint(10, 100)
        fuzz_input = "".join(random.choice(chars) for _ in range(length))
        result = run(["python3", PROCESS_PATH, fuzz_input], text=True)
        assert result.returncode == 0, f"Agent script failed on input {fuzz_input}\nStderr: {result.stderr}"
        assert result.stdout.strip() == expected_hash(fuzz_input), (
            f"Mismatch on input: {fuzz_input}\n"
            f"Expected: {expected_hash(fuzz_input)}\nGot: {result.stdout.strip()}"
        )


def branches_include_main(trigger):
    if trigger is None:
        return False
    if isinstance(trigger, str):
        return trigger == "main"
    if isinstance(trigger, list):
        return "main" in trigger
    if isinstance(trigger, dict):
        branches = trigger.get("branches")
        if isinstance(branches, str):
            return branches == "main"
        return isinstance(branches, list) and "main" in branches
    return False


def test_ci_yml_contents_and_execution():
    assert os.path.isfile(CI_PATH), f"Expected CI workflow file {CI_PATH} to exist."
    content = open(CI_PATH, encoding="utf-8").read()

    # Preserve the original content assertions in addition to structural checks.
    assert "C-Extension CI" in content
    assert "push" in content
    assert "pull_request" in content
    assert "main" in content
    assert "ubuntu-latest" in content
    assert "actions/checkout@v3" in content
    assert "make" in content
    assert 'python3 process.py "test_string"' in content or "python3 process.py 'test_string'" in content

    workflow = yaml.safe_load(content)
    assert isinstance(workflow, dict), "ci.yml must parse as a YAML mapping"
    assert workflow.get("name") == "C-Extension CI"
    triggers = workflow.get("on", workflow.get(True))  # PyYAML 1.1 treats 'on' as boolean.
    assert isinstance(triggers, dict), "Workflow 'on' section must be a mapping"
    assert branches_include_main(triggers.get("push")), "push must target main"
    assert branches_include_main(triggers.get("pull_request")), "pull_request must target main"

    jobs = workflow.get("jobs")
    assert isinstance(jobs, dict) and set(jobs) == {"build-and-test"}, \
        "Workflow must contain only the build-and-test job"
    job = jobs["build-and-test"]
    assert job.get("runs-on") == "ubuntu-latest"
    steps = job.get("steps")
    assert isinstance(steps, list) and steps, "build-and-test must contain steps"

    checkout_indexes = [i for i, step in enumerate(steps)
                        if isinstance(step, dict) and step.get("uses") == "actions/checkout@v3"]
    run_indexes = [(i, step) for i, step in enumerate(steps)
                   if isinstance(step, dict) and isinstance(step.get("run"), str)]
    make_indexes = [i for i, step in run_indexes if re.search(r'(^|[;&|\s])make([;&|\s]|$)', step["run"])]
    test_indexes = [i for i, step in run_indexes
                    if 'python3 process.py "test_string"' in step["run"]
                    or "python3 process.py 'test_string'" in step["run"]]
    assert checkout_indexes, "Missing actions/checkout@v3 step"
    assert make_indexes, "Missing make step"
    assert test_indexes, "Missing process.py test step"
    assert checkout_indexes[0] < make_indexes[0] < test_indexes[0], \
        "Checkout, build, and test steps must occur in that order"

    with tempfile.TemporaryDirectory() as repo:
        shutil.copytree(LIB_DIR, os.path.join(repo, "c-string-hasher"))
        staged_lib = os.path.join(repo, "c-string-hasher", "libhasher.so")
        if os.path.exists(staged_lib):
            os.unlink(staged_lib)
        shutil.copy2(PROCESS_PATH, os.path.join(repo, "process.py"))

        job_default_wd = (((job.get("defaults") or {}).get("run") or {}).get("working-directory"))
        for _, step in run_indexes:
            wd = step.get("working-directory", job_default_wd)
            cwd = os.path.join(repo, wd) if wd else repo
            assert os.path.isdir(cwd), f"Workflow working-directory does not exist: {wd}"
            result = run(["bash", "-eo", "pipefail", "-c", step["run"]], cwd=cwd, text=True)
            assert result.returncode == 0, (
                f"Workflow command failed: {step['run']}\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        assert os.path.isfile(staged_lib), \
            "Executing the workflow did not build c-string-hasher/libhasher.so"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
