#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile

DOCS_DIR = "/home/user/docs_project"
CPP_FILE = "/home/user/parser.cpp"
EXECUTABLE = "/home/user/parser"


def run_parser(executable, gcode, expected):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".gcode", delete=False) as f:
        f.write(gcode)
        input_path = f.name

    try:
        result = subprocess.run(
            [executable, input_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
    finally:
        os.unlink(input_path)

    assert result.returncode == 0, (
        f"Parser {executable} exited with {result.returncode}. "
        f"stderr: {result.stderr.decode(errors='replace')}"
    )
    output = result.stdout.decode(errors="strict")
    assert output in (str(expected), str(expected) + "\n"), (
        f"Parser {executable} must print only {expected}, but printed {output!r}."
    )


def test_parser_exists():
    assert os.path.isfile(CPP_FILE), f"Source file {CPP_FILE} is missing."
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_parser_behavior_and_source_compiles():
    fd, rebuilt = tempfile.mkstemp(prefix="rebuilt_parser_")
    os.close(fd)
    os.unlink(rebuilt)
    try:
        compilation = subprocess.run(
            ["g++", "-std=c++17", "-O2", CPP_FILE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
            check=False,
        )
        assert compilation.returncode == 0, (
            "parser.cpp does not compile successfully: "
            + compilation.stderr.decode(errors="replace")
        )

        rng = random.SystemRandom()
        first = rng.randint(101, 900000)
        second = rng.randint(101, 900000)
        third = rng.randint(101, 900000)
        expected = first + second + third
        gcode = (
            "; FLAVOR:Marlin\n"
            f"; TIME:{first}\n"
            "G28 ; home axes\n"
            f"; TIME:{second}\n"
            "; TIME:0\n"
            f"; TIME:{third}\n"
            "; TIME: 700\n"
            " ; TIME:800\n"
            ";TIME:900\n"
            "; TIME:1000 extra\n"
            "G1 X1 ; TIME:1100\n"
            "; TIME:12.5\n"
        )

        # Exercise both the submitted executable and a fresh build of its source.
        run_parser(EXECUTABLE, gcode, expected)
        run_parser(rebuilt, gcode, expected)

        model_path = os.path.join(DOCS_DIR, "model_v2.gcode")
        result = subprocess.run(
            [EXECUTABLE, model_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
            check=False,
        )
        assert result.returncode == 0, f"Parser failed on {model_path}."
        model_output = result.stdout.decode(errors="strict")
        assert model_output in ("2438", "2438\n"), (
            f"Parser produced {model_output!r} for model_v2.gcode instead of 2438."
        )
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)


def test_symlink_latest_elf():
    symlink_path = os.path.join(DOCS_DIR, "latest.elf")

    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)
    assert os.path.basename(target) == "fw_v2.elf", f"Symlink {symlink_path} does not point to fw_v2.elf."


def test_hardlink_model_backup():
    backup_path = os.path.join(DOCS_DIR, "model_backup.gcode")
    original_path = os.path.join(DOCS_DIR, "model_v2.gcode")

    assert os.path.exists(backup_path), f"Hard link {backup_path} does not exist."
    assert not os.path.islink(backup_path), f"{backup_path} should be a hard link, not a symlink."
    assert os.path.samefile(backup_path, original_path), f"{backup_path} does not point to the same inode as {original_path}."


def test_index_md_updated():
    index_md = os.path.join(DOCS_DIR, "index.md")
    assert os.path.exists(index_md), f"{index_md} does not exist."

    with open(index_md, "r") as f:
        content = f.read()

    assert "2438" in content, f"Expected print time '2438' not found in {index_md}. Content: {content}"
    assert "latest.elf" in content, f"Expected string 'latest.elf' not found in {index_md}. Content: {content}"
    assert "{{PRINT_TIME}}" not in content, f"Placeholder {{{{PRINT_TIME}}}} was not replaced."
    assert "{{LATEST_FIRMWARE}}" not in content, f"Placeholder {{{{LATEST_FIRMWARE}}}} was not replaced."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
