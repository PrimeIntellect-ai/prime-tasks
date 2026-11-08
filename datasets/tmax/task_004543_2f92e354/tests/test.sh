#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import shutil
import subprocess

SCRIPT = '/home/user/fix_and_build.sh'
PROJECT = '/home/user/project'
LIB = PROJECT + '/lib/libmathops.so'
APP = PROJECT + '/calc_app'
RESULT = '/home/user/result.txt'
SOURCE = PROJECT + '/rust_src/main.rs'

BROKEN_SOURCE = '''#[link(name = "mathops")]
extern {
    fn multiply(a: i32, b: i32) -> i32;
}

fn parse_and_calc(expr: &String) -> i32 {
    let parts: Vec<&str> = expr.split_whitespace().collect();
    if parts.len() == 5 {
        let a: i32 = parts[0].parse().unwrap();
        let b: i32 = parts[2].parse().unwrap();
        let c: i32 = parts[4].parse().unwrap();
        let mult_res = unsafe { multiply(b, c) };
        a + mult_res
    } else {
        0
    }
}

fn main() {
    let expr = String::from("10 + 20 * 3");
    let s = expr; // Value moved here
    let res = parse_and_calc(&expr); // Borrow checker error
    println!("{}", res);
}
'''


def clean_env():
    env = os.environ.copy()
    env.pop('LD_LIBRARY_PATH', None)
    env.pop('LD_PRELOAD', None)
    return env


def test_01_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_02_script_performs_pipeline_from_broken_sources():
    with open(SOURCE, 'w') as f:
        f.write(BROKEN_SOURCE)
    shutil.rmtree(PROJECT + '/lib', ignore_errors=True)
    for path in (APP, RESULT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    completed = subprocess.run(
        [SCRIPT], cwd='/home/user', env=clean_env(),
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120
    )
    assert completed.returncode == 0, (
        f"Build script failed with exit code {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_03_shared_library_exists():
    assert os.path.isfile(LIB), f"Shared library {LIB} does not exist."


def test_04_executable_exists_and_executable():
    assert os.path.isfile(APP), f"Executable {APP} does not exist."
    assert os.access(APP, os.X_OK), f"Executable {APP} is not executable."


def test_05_shared_library_is_real_and_exports_working_multiply():
    with open(LIB, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'libmathops.so is not an ELF file.'
    header = subprocess.run(
        ['readelf', '-h', LIB], check=True, capture_output=True, text=True
    ).stdout
    assert re.search(r'^\s*Type:\s+DYN\b', header, re.MULTILINE), \
        'libmathops.so is not an ELF shared object.'

    library = ctypes.CDLL(LIB)
    multiply = library.multiply
    multiply.argtypes = [ctypes.c_int, ctypes.c_int]
    multiply.restype = ctypes.c_int
    for a, b in [(7, 9), (-4, 6), (0, 123)]:
        assert multiply(a, b) == a * b


def test_06_executable_links_to_library_and_has_working_rpath():
    with open(APP, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'calc_app is not an ELF executable.'

    dynamic = subprocess.run(
        ['readelf', '-d', APP], check=True, capture_output=True, text=True
    ).stdout
    assert re.search(r'\(NEEDED\).*\[libmathops\.so\]', dynamic), \
        'calc_app does not declare libmathops.so as a dynamic dependency.'
    rpaths = re.findall(r'\((?:RUNPATH|RPATH)\).*\[([^]]+)\]', dynamic)
    assert rpaths, 'calc_app has no RPATH or RUNPATH for its shared library.'
    expanded = []
    for value in rpaths:
        for entry in value.split(':'):
            entry = entry.replace('${ORIGIN}', PROJECT).replace('$ORIGIN', PROJECT)
            expanded.append(os.path.realpath(entry))
    assert os.path.realpath(PROJECT + '/lib') in expanded, \
        'calc_app RPATH/RUNPATH does not include the project lib directory.'

    linked = subprocess.run(
        ['ldd', APP], env=clean_env(), check=True, capture_output=True, text=True
    ).stdout
    match = re.search(r'libmathops\.so\s+=>\s+(\S+)', linked)
    assert match and match.group(1) != 'not', 'libmathops.so was not resolved by the loader.'
    assert os.path.realpath(match.group(1)) == os.path.realpath(LIB), \
        f"calc_app resolved libmathops.so from the wrong location: {match.group(1)}"


def test_07_executable_runs_without_global_loader_state():
    library = ctypes.CDLL(LIB)
    library.multiply.argtypes = [ctypes.c_int, ctypes.c_int]
    library.multiply.restype = ctypes.c_int
    expected = str(10 + library.multiply(20, 3))
    completed = subprocess.run(
        [APP], cwd='/tmp', env=clean_env(), check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert completed.stdout.strip() == expected


def test_08_result_file_correct():
    assert os.path.isfile(RESULT), f"Result file {RESULT} does not exist. Did you run your script?"
    with open(RESULT, 'r') as f:
        content = f.read().strip()
    assert content == "70", f"Expected result to be '70', but got '{content}'."

    actual = subprocess.run(
        [APP], cwd='/tmp', env=clean_env(), check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    ).stdout.strip()
    assert content == actual, 'result.txt does not contain calc_app output.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
