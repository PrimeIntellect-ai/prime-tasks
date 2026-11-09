#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile


def test_status_txt_contains_ok():
    status_file = "/home/user/status.txt"
    assert os.path.isfile(status_file), f"{status_file} does not exist. Did you run your verify.sh script?"

    with open(status_file, "r") as f:
        content = f.read().strip()

    assert content == "OK", f"Expected '{status_file}' to contain exactly 'OK', but found '{content}'"


def test_make_target_minimal_really_builds_elf():
    src_dir = "/home/user/src"
    binary_path = os.path.join(src_dir, "util_min")

    dry = subprocess.run(
        ["make", "-n", "target_minimal"], cwd=src_dir,
        capture_output=True, text=True
    )
    assert dry.returncode == 0, f"make target_minimal is invalid:\n{dry.stdout}\n{dry.stderr}"
    commands = dry.stdout + "\n" + dry.stderr
    assert re.search(r"(?:^|\s)-D\s*MINIMAL_BUILD(?:\s|$)|(?:^|\s)-DMINIMAL_BUILD(?:\s|$)", commands), \
        "target_minimal does not compile with the MINIMAL_BUILD macro defined"
    assert not re.search(r"(?:^|\s)-lm(?:\s|$)", commands), \
        "target_minimal links against the math library"
    assert "main.c" in commands and "util_min" in commands, \
        "target_minimal does not show a command compiling main.c into util_min"
    assert re.search(r"(?:^|[\s/])strip(?:\s|$)", commands), \
        "target_minimal does not use strip on the resulting binary"

    if os.path.lexists(binary_path):
        os.remove(binary_path)
    built = subprocess.run(
        ["make", "target_minimal"], cwd=src_dir,
        capture_output=True, text=True
    )
    assert built.returncode == 0, f"make target_minimal failed:\n{built.stdout}\n{built.stderr}"
    assert os.path.isfile(binary_path), "make target_minimal did not create util_min"
    assert os.access(binary_path, os.X_OK), "util_min is not executable"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "util_min is not a compiled ELF binary"


def test_util_min_binary_exists_and_size():
    binary_path = "/home/user/src/util_min"
    assert os.path.isfile(binary_path), f"{binary_path} does not exist. Did you run 'make target_minimal'?"

    size = os.path.getsize(binary_path)
    assert size < 20480, f"Binary {binary_path} is too large: {size} bytes (expected < 20480 bytes). Did you strip it?"


def test_util_min_not_linked_to_libm():
    binary_path = "/home/user/src/util_min"
    assert os.path.isfile(binary_path), f"{binary_path} does not exist."

    result = subprocess.run(["ldd", binary_path], capture_output=True, text=True)
    # ldd might fail if not a dynamic executable, which is fine if statically linked without libm
    if result.returncode == 0:
        assert "libm.so" not in result.stdout, f"{binary_path} is dynamically linked to libm.so, which violates constraints."


def test_util_min_is_stripped():
    binary_path = "/home/user/src/util_min"
    assert os.path.isfile(binary_path), f"{binary_path} does not exist."

    result = subprocess.run(["file", binary_path], capture_output=True, text=True)
    assert "not stripped" not in result.stdout, f"{binary_path} has not been stripped of symbols."
    assert "ELF" in result.stdout and "stripped" in result.stdout, \
        f"{binary_path} is not a stripped ELF binary: {result.stdout}"


def test_verify_sh_exists_and_executable():
    script_path = "/home/user/verify.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."
    with open(script_path, "r", errors="replace") as f:
        script = f.read()
    assert re.search(r"\bldd\b", script), "verify.sh does not use ldd as required"


def test_minimal_build_macro_used():
    binary_path = "/home/user/src/util_min"
    assert os.path.isfile(binary_path), f"{binary_path} does not exist."

    # Run the binary and check output to ensure MINIMAL_BUILD was defined
    result = subprocess.run([binary_path], capture_output=True, text=True)
    assert "Minimal mode active." in result.stdout, "The binary does not print 'Minimal mode active.', indicating MINIMAL_BUILD was not defined during compilation."


def test_verify_sh_actually_validates_constraints():
    binary_path = "/home/user/src/util_min"
    script_path = "/home/user/verify.sh"
    status_path = "/home/user/status.txt"

    with tempfile.TemporaryDirectory() as td:
        saved_binary = os.path.join(td, "util_min")
        shutil.copy2(binary_path, saved_binary)

        try:
            # A valid executable made too large must not result in OK.
            with open(binary_path, "ab") as f:
                current = os.path.getsize(binary_path)
                f.write(b"\0" * (20480 - current if current < 20480 else 1))
            if os.path.exists(status_path):
                os.remove(status_path)
            subprocess.run([script_path], cwd="/home/user", capture_output=True, text=True)
            assert not os.path.exists(status_path) or open(status_path).read().strip() != "OK", \
                "verify.sh wrote OK for a binary that is not smaller than 20,480 bytes"

            # A small ELF that dynamically needs libm must not result in OK.
            probe_c = os.path.join(td, "libm_probe.c")
            probe_bin = os.path.join(td, "libm_probe")
            with open(probe_c, "w") as f:
                f.write('#include <math.h>\nint main(int argc, char **argv) { volatile double x = argc; return cos(x) > 2.0; }\n')
            compile_result = subprocess.run(
                ["gcc", probe_c, "-Wl,--no-as-needed", "-lm", "-o", probe_bin],
                capture_output=True, text=True
            )
            assert compile_result.returncode == 0, compile_result.stderr
            subprocess.run(["strip", probe_bin], check=True)
            assert os.path.getsize(probe_bin) < 20480, "Internal libm test executable is unexpectedly too large"
            linked = subprocess.run(["ldd", probe_bin], capture_output=True, text=True)
            assert "libm.so" in linked.stdout, "Internal libm test executable does not link to libm"
            shutil.copy2(probe_bin, binary_path)
            if os.path.exists(status_path):
                os.remove(status_path)
            subprocess.run([script_path], cwd="/home/user", capture_output=True, text=True)
            assert not os.path.exists(status_path) or open(status_path).read().strip() != "OK", \
                "verify.sh wrote OK for a binary dynamically linked to libm.so"
        finally:
            shutil.copy2(saved_binary, binary_path)

    # Finally, the submitted script must itself produce the required status for
    # the restored valid minimal binary.
    if os.path.exists(status_path):
        os.remove(status_path)
    result = subprocess.run([script_path], cwd="/home/user", capture_output=True, text=True)
    assert result.returncode == 0, f"verify.sh failed for the valid util_min:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(status_path), "verify.sh did not create /home/user/status.txt"
    with open(status_path, "r") as f:
        assert f.read().strip() == "OK", "verify.sh did not write OK for the valid util_min"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
