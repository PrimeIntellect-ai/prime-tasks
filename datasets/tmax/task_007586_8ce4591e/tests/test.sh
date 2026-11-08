#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/sec_lib")
SCRIPT = PROJECT / "run_tool.sh"
TOOL = PROJECT / "urltool"
LIB = PROJECT / "liburlsec.so"
OUTPUT = PROJECT / "output.txt"
PAYLOAD = "javascript:<script>alert(1)</script>"
PAYLOAD_EXPECTED = "javascript:%3Cscript%3Ealert(1)%3C/script%3E\n"


def encode_expected(value):
    return value.replace("<", "%3C").replace(">", "%3E") + "\n"


def run_script(args, timeout=10):
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return subprocess.run(
        [str(SCRIPT), *args],
        cwd="/tmp",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def test_output_txt_exists_and_content():
    path = "/home/user/sec_lib/output.txt"
    assert os.path.isfile(path), f"{path} is missing. The script may not have been run or output redirection failed."

    with open(path, "r") as f:
        content = f.read()

    expected_content = "javascript:%3Cscript%3Ealert(1)%3C/script%3E\n"
    assert content == expected_content, f"Content of {path} is incorrect. Expected '{expected_content}', but got '{content}'."


def test_run_tool_sh_exists_and_executable():
    path = "/home/user/sec_lib/run_tool.sh"
    assert os.path.isfile(path), f"{path} is missing. The bash script was not created."

    st = os.stat(path)
    assert st.st_mode & stat.S_IXUSR, f"{path} is not executable. Run 'chmod +x {path}'."


def test_compiled_artifacts_exist():
    lib_path = "/home/user/sec_lib/liburlsec.so"
    tool_path = "/home/user/sec_lib/urltool"

    assert os.path.isfile(lib_path), f"{lib_path} is missing. The Makefile may not have built the shared library successfully."
    assert os.path.isfile(tool_path), f"{tool_path} is missing. The Makefile may not have built the executable successfully."


def test_makefile_rebuilds_real_linked_artifacts():
    makefile = PROJECT / "Makefile"
    assert makefile.is_file(), "Makefile is missing"

    dry = subprocess.run(
        ["make", "-B", "--dry-run"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
    )
    assert dry.returncode == 0, f"Makefile dry run failed:\n{dry.stdout}"
    commands = dry.stdout
    assert re.search(r"-f(?:PIC|pic)(?:\s|$)", commands), "The shared-library build does not use position-independent code (-fPIC)"
    assert "-shared" in commands, "The Makefile does not issue a shared-library link command"
    assert "urlsec.c" in commands, "The Makefile does not build the library from urlsec.c"
    assert "main.c" in commands, "The Makefile does not build the program from main.c"
    assert "-lurlsec" in commands or re.search(r"(?:^|[\s/])liburlsec\.so(?:\s|$)", commands), \
        "The executable link command does not link liburlsec"

    for artifact in (TOOL, LIB):
        if artifact.exists() or artifact.is_symlink():
            artifact.unlink()

    built = subprocess.run(
        ["make", "-B"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert built.returncode == 0, f"make failed:\n{built.stdout}"
    assert LIB.is_file(), "make did not recreate liburlsec.so"
    assert TOOL.is_file(), "make did not recreate urltool"
    assert LIB.read_bytes()[:4] == b"\x7fELF", "liburlsec.so is not an ELF binary"
    assert TOOL.read_bytes()[:4] == b"\x7fELF", "urltool is not an ELF binary"
    assert os.access(TOOL, os.X_OK), "urltool is not executable"

    lib_header = subprocess.run(
        ["readelf", "-h", str(LIB)], text=True, capture_output=True, timeout=10
    )
    assert lib_header.returncode == 0 and re.search(r"Type:\s+DYN", lib_header.stdout), \
        "liburlsec.so is not an ELF shared object"

    symbols = subprocess.run(
        ["readelf", "-Ws", str(LIB)], text=True, capture_output=True, timeout=10
    )
    assert symbols.returncode == 0 and re.search(r"\bGLOBAL\b.*\bencode_xss\b", symbols.stdout), \
        "liburlsec.so does not export encode_xss"

    dynamic = subprocess.run(
        ["readelf", "-d", str(TOOL)], text=True, capture_output=True, timeout=10
    )
    assert dynamic.returncode == 0, f"Cannot inspect urltool dynamic linkage: {dynamic.stderr}"
    assert re.search(r"NEEDED.*\[liburlsec\.so\]", dynamic.stdout), \
        "urltool is not dynamically linked against liburlsec.so"


def test_tool_and_script_behavior_and_argument_handling():
    random_inputs = [
        "plain-" + secrets.token_hex(12),
        "<" + secrets.token_hex(8) + ">",
        "a b;$()'\"<tag>" + secrets.token_hex(8) + "</tag>",
        "x<<" + secrets.token_hex(10) + ">>y",
    ]

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = str(PROJECT)
    for value in random_inputs:
        direct = subprocess.run(
            [str(TOOL), value],
            cwd="/tmp",
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert direct.returncode == 0, f"urltool failed for a generated input: {direct.stderr}"
        assert direct.stdout == encode_expected(value), "urltool returned an incorrect generated result"

    assert run_script([]).returncode != 0, "run_tool.sh must reject zero arguments"
    assert run_script(["one", "two"]).returncode != 0, "run_tool.sh must reject more than one argument"

    backup = PROJECT / (".urltool.verifier-backup-" + secrets.token_hex(8))
    marker_arg = "probe-" + secrets.token_hex(16)
    os.replace(TOOL, backup)
    try:
        TOOL.write_text("#!/bin/sh\n[ \"$#\" -eq 1 ] || exit 73\nprintf 'PROBE:%s\\n' \"$1\"\n")
        TOOL.chmod(0o755)
        probed = run_script([marker_arg])
        assert probed.returncode == 0, f"run_tool.sh did not execute the project urltool: {probed.stderr.decode(errors='replace')}"
        assert OUTPUT.is_file(), "run_tool.sh did not create output.txt"
        assert OUTPUT.read_text() == f"PROBE:{marker_arg}\n", \
            "run_tool.sh does not redirect the invoked urltool's standard output to output.txt"
    finally:
        if TOOL.exists() or TOOL.is_symlink():
            TOOL.unlink()
        os.replace(backup, TOOL)

    for value in random_inputs:
        completed = run_script([value])
        assert completed.returncode == 0, \
            f"run_tool.sh failed from another working directory without inherited LD_LIBRARY_PATH: {completed.stderr.decode(errors='replace')}"
        assert OUTPUT.read_text() == encode_expected(value), "run_tool.sh produced an incorrect generated result"

    final = run_script([PAYLOAD])
    assert final.returncode == 0, f"run_tool.sh failed for the prescribed payload: {final.stderr.decode(errors='replace')}"
    assert OUTPUT.read_text() == PAYLOAD_EXPECTED, "The final prescribed output is incorrect"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
