#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import glob
import importlib
import importlib.machinery
import os
import shutil
import subprocess
import sys
import tempfile

PROJECT = "/home/user/project"


def adler32_reference(data):
    a = 1
    b = 0
    for byte in data:
        a = (a + byte) % 65521
        b = (b + a) % 65521
    return (b << 16) | a


def expected_comparisons():
    data_a = os.path.join(PROJECT, "data_a")
    data_b = os.path.join(PROJECT, "data_b")
    result = []
    for name in sorted(os.listdir(data_a)):
        path_a = os.path.join(data_a, name)
        path_b = os.path.join(data_b, name)
        if not os.path.isfile(path_a):
            continue
        assert os.path.isfile(path_b), f"Missing corresponding file: {path_b}"
        with open(path_a, "rb") as f:
            checksum_a = adler32_reference(f.read())
        with open(path_b, "rb") as f:
            checksum_b = adler32_reference(f.read())
        status = "MATCH" if checksum_a == checksum_b else "MISMATCH"
        result.append(f"{name}: {status}")
    return result


def test_adler32_c_fixed():
    c_file = "/home/user/project/adler32.c"
    assert os.path.isfile(c_file), f"File {c_file} does not exist."

    with open(c_file, "r") as f:
        content = f.read()

    assert "65521" in content, "The C file was not fixed to use the correct MOD_ADLER value (65521)."
    assert "65536" not in content, "The C file still contains the buggy MOD_ADLER value (65536)."


def test_setup_py_fixed():
    setup_file = "/home/user/project/setup.py"
    assert os.path.isfile(setup_file), f"File {setup_file} does not exist."

    with open(setup_file, "r") as f:
        content = f.read()

    assert "adler32.c" in content, "The setup.py file was not fixed to reference 'adler32.c'."
    assert "wrong_file.c" not in content, "The setup.py file still references 'wrong_file.c'."


def test_module_built():
    so_files = glob.glob("/home/user/project/adler32_fast*.so")
    assert len(so_files) > 0, "The adler32_fast module was not built in-place."


def test_compiled_module_functionality():
    sys.modules.pop("adler32_fast", None)
    sys.path.insert(0, PROJECT)
    try:
        module = importlib.import_module("adler32_fast")
    finally:
        sys.path.pop(0)

    origin = os.path.realpath(module.__file__)
    assert any(origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), (
        f"adler32_fast was not imported from a compiled extension: {origin}"
    )
    assert callable(getattr(module, "checksum", None)), "adler32_fast.checksum is missing or not callable."

    payloads = [
        b"",
        b"hello world",
        bytes(range(256)),
        b"\xff" * 70000,
        bytes((i * 73 + 19) % 256 for i in range(150000)),
    ]
    for payload in payloads:
        assert module.checksum(payload) == adler32_reference(payload), (
            f"Incorrect Adler-32 result for a payload of length {len(payload)}."
        )


def test_compare_sh_exists_and_executable():
    script_file = "/home/user/project/compare.sh"
    assert os.path.isfile(script_file), f"Script {script_file} does not exist."
    assert os.access(script_file, os.X_OK), f"Script {script_file} is not executable."
    with open(script_file, "r") as f:
        content = f.read()
    assert "zlib" not in content.lower(), "compare.sh must not use zlib."
    assert "adler32_fast" in content, "compare.sh does not reference adler32_fast."
    assert "checksum" in content, "compare.sh does not call the checksum function."


def test_compare_sh_runs_on_real_data():
    completed = subprocess.run(
        [os.path.join(PROJECT, "compare.sh")],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, f"compare.sh failed:\n{completed.stderr}"
    lines = completed.stdout.splitlines()
    assert sorted(lines) == expected_comparisons(), (
        f"compare.sh produced incorrect output. Got: {lines}"
    )


def test_comparison_results():
    results_file = "/home/user/project/comparison_results.txt"
    assert os.path.isfile(results_file), f"Results file {results_file} does not exist."

    with open(results_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "file1.txt: MATCH",
        "file2.txt: MISMATCH",
        "file3.txt: MATCH"
    ]

    assert lines == expected_lines, (
        f"The contents of {results_file} do not match the expected sorted output.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {lines}"
    )

    with open(results_file, "r") as f:
        raw_lines = f.read().splitlines()
    assert raw_lines == expected_comparisons(), (
        "comparison_results.txt must contain exactly the sorted, dynamically derived report lines."
    )


def test_compare_sh_uses_adler32_fast_results():
    backup = tempfile.mkdtemp(prefix="adler32-verifier-")
    data_a = os.path.join(PROJECT, "data_a")
    data_b = os.path.join(PROJECT, "data_b")
    saved_a = os.path.join(backup, "data_a")
    saved_b = os.path.join(backup, "data_b")
    module_paths = glob.glob(os.path.join(PROJECT, "adler32_fast*.so"))
    source_module = os.path.join(PROJECT, "adler32_fast.py")
    if os.path.exists(source_module):
        module_paths.append(source_module)
    moved_modules = []
    fake_module = source_module
    call_log = os.path.join(backup, "calls.log")

    try:
        shutil.move(data_a, saved_a)
        shutil.move(data_b, saved_b)
        os.mkdir(data_a)
        os.mkdir(data_b)

        cases = {
            "a_equal.bin": (b"same-input", b"same-input", "MATCH"),
            "b_collision.bin": (b"left-collision", b"right-collision", "MATCH"),
            "c_different.bin": (b"different-a", b"different-b", "MISMATCH"),
        }
        for name, (left, right, _) in cases.items():
            with open(os.path.join(data_a, name), "wb") as f:
                f.write(left)
            with open(os.path.join(data_b, name), "wb") as f:
                f.write(right)

        for index, path in enumerate(module_paths):
            destination = os.path.join(backup, f"module-{index}-{os.path.basename(path)}")
            shutil.move(path, destination)
            moved_modules.append((destination, path))

        with open(fake_module, "w") as f:
            f.write(
                "import os\n"
                "def checksum(data):\n"
                "    with open(os.environ['ADLER_CALL_LOG'], 'a') as log:\n"
                "        log.write(data.hex() + '\\n')\n"
                "    special = {\n"
                "        b'left-collision': 424242,\n"
                "        b'right-collision': 424242,\n"
                "        b'different-a': 111,\n"
                "        b'different-b': 222,\n"
                "    }\n"
                "    return special.get(data, 999999)\n"
            )

        env = os.environ.copy()
        env["ADLER_CALL_LOG"] = call_log
        env["PYTHONPATH"] = PROJECT + os.pathsep + env.get("PYTHONPATH", "")
        completed = subprocess.run(
            [os.path.join(PROJECT, "compare.sh")],
            cwd=PROJECT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert completed.returncode == 0, f"compare.sh failed with an instrumented module:\n{completed.stderr}"
        expected = [f"{name}: {values[2]}" for name, values in sorted(cases.items())]
        assert sorted(completed.stdout.splitlines()) == expected, (
            "compare.sh did not base its comparisons on adler32_fast.checksum return values."
        )

        assert os.path.isfile(call_log), "compare.sh never called adler32_fast.checksum."
        with open(call_log, "r") as f:
            calls = collections.Counter(line.strip() for line in f if line.strip())
        required = collections.Counter()
        for left, right, _ in cases.values():
            required[left.hex()] += 1
            required[right.hex()] += 1
        for value, count in required.items():
            assert calls[value] >= count, "compare.sh did not checksum both files in every pair."
    finally:
        if os.path.exists(fake_module):
            os.remove(fake_module)
        if os.path.exists(data_a):
            shutil.rmtree(data_a)
        if os.path.exists(data_b):
            shutil.rmtree(data_b)
        if os.path.exists(saved_a):
            shutil.move(saved_a, data_a)
        if os.path.exists(saved_b):
            shutil.move(saved_b, data_b)
        for saved, original in moved_modules:
            if os.path.exists(saved):
                shutil.move(saved, original)
        shutil.rmtree(backup, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
