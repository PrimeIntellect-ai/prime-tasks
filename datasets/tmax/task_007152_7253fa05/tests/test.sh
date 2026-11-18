#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import struct
import subprocess
import tempfile
import random

TOOL_DIR = "/home/user/log_tool"


def test_fuzzer_script_exists_and_reproduces_crash():
    fuzzer_path = os.path.join(TOOL_DIR, "fuzzer.py")
    assert os.path.isfile(fuzzer_path), f"Fuzzer script not found at {fuzzer_path}"
    assert os.access(fuzzer_path, os.X_OK), "fuzzer.py must be executable"

    with open(fuzzer_path, "r") as f:
        content = f.read()
    assert "import" in content or "print" in content or "subprocess" in content, \
        "Fuzzer script does not look like valid Python code"

    # Exercise the standalone fuzzer against a controlled ./log_processor. The
    # mock succeeds twice and then reports a segfault, proving the fuzzer keeps
    # generating inputs until it observes return code 139.
    with tempfile.TemporaryDirectory() as td:
        copied_fuzzer = os.path.join(td, "fuzzer.py")
        shutil.copy2(fuzzer_path, copied_fuzzer)

        mock_processor = os.path.join(td, "log_processor")
        with open(mock_processor, "w") as f:
            f.write("""#!/bin/bash
input=$(cat)
printf '%s\\n' "$input" >> calls.txt
count=$(wc -l < calls.txt)
if [ "$count" -ge 3 ]; then
    exit 139
fi
exit 0
""")
        os.chmod(mock_processor, 0o755)

        result = subprocess.run(
            [copied_fuzzer], cwd=td, capture_output=True, text=True, timeout=15
        )
        assert result.returncode == 0, \
            f"fuzzer.py did not successfully detect the simulated segfault:\n{result.stdout}\n{result.stderr}"

        calls_path = os.path.join(td, "calls.txt")
        assert os.path.isfile(calls_path), "fuzzer.py did not execute ./log_processor"
        with open(calls_path) as f:
            calls = [line.strip() for line in f if line.strip()]
        assert len(calls) >= 3, "fuzzer.py did not continue until the crash was reproduced"
        assert all(re.fullmatch(r"[0-9a-fA-F]{16}", value) for value in calls), \
            "fuzzer.py must feed random 16-character valid hexadecimal strings"


def test_makefile_fixed():
    makefile_path = os.path.join(TOOL_DIR, "Makefile")
    assert os.path.isfile(makefile_path), f"Makefile not found at {makefile_path}"

    with open(makefile_path, "r") as f:
        content = f.read()
    assert "-lm" in content, "Makefile does not link the math library (-lm). The build will fail."


def test_c_code_fixed():
    c_file_path = os.path.join(TOOL_DIR, "log_processor.c")
    assert os.path.isfile(c_file_path), f"C source file not found at {c_file_path}"

    with open(c_file_path, "r") as f:
        content = f.read()
    assert "5 / 9" not in content, \
        "The integer division bug (5 / 9) is still present in log_processor.c"
    assert "(unsigned int*)&out_buffer[i]" not in content, \
        "The memory corruption bug in sscanf is still present in log_processor.c"


def test_executable_compiles_and_runs():
    exe_path = os.path.join(TOOL_DIR, "log_processor")
    if os.path.lexists(exe_path):
        os.remove(exe_path)

    make_result = subprocess.run(["make"], cwd=TOOL_DIR, capture_output=True, text=True)
    assert make_result.returncode == 0, f"make failed:\n{make_result.stderr}"
    assert os.path.isfile(exe_path), "log_processor executable was not built"
    assert os.access(exe_path, os.X_OK), "log_processor is not executable"
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "log_processor is not a compiled ELF executable"

    raw_logs_path = os.path.join(TOOL_DIR, "raw_logs.txt")
    with open(raw_logs_path, "r") as f:
        raw_logs_data = f.read()
    run_result = subprocess.run([exe_path], input=raw_logs_data, capture_output=True, text=True)
    assert run_result.returncode == 0, f"log_processor crashed or failed:\n{run_result.stderr}"
    expected_output = "N: 10, Adj: 5.00\nN: 20, Adj: 20.00\nN: 5, Adj: 1.25\n"
    assert run_result.stdout == expected_output, \
        f"log_processor produced incorrect output:\n{run_result.stdout}"

    # Test many verifier-derived records, rather than only the three provided
    # lines. Values are multiples of 1.5, making the expected adjusted result
    # exactly 1.25*k^2 while covering positive and negative floats and varied N.
    rng = random.Random(918273)
    records = []
    expected_lines = []
    for _ in range(40):
        n = rng.randint(-2000000000, 2000000000)
        k = rng.choice([x for x in range(-100, 101) if x != 0])
        value = 1.5 * k
        records.append(struct.pack("<if", n, value).hex())
        expected_lines.append(f"N: {n}, Adj: {1.25 * k * k:.2f}")

    dynamic_input = "\n".join(records) + "\n"
    dynamic_result = subprocess.run(
        [exe_path], input=dynamic_input, capture_output=True, text=True, timeout=10
    )
    assert dynamic_result.returncode == 0, \
        f"log_processor failed on generated valid records:\n{dynamic_result.stderr}"
    assert dynamic_result.stdout == "\n".join(expected_lines) + "\n", \
        f"log_processor did not correctly decode and adjust generated records:\n{dynamic_result.stdout}"


def test_fixed_metrics_file():
    metrics_path = os.path.join(TOOL_DIR, "fixed_metrics.txt")
    assert os.path.isfile(metrics_path), f"Output file not found at {metrics_path}"

    with open(metrics_path, "r") as f:
        content = f.read()
    expected_output = "N: 10, Adj: 5.00\nN: 20, Adj: 20.00\nN: 5, Adj: 1.25\n"
    assert content.strip() == expected_output.strip(), \
        f"The contents of {metrics_path} do not match the expected output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
