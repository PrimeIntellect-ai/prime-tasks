#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pathlib
import shutil
import subprocess
import tempfile

SUMMARY = pathlib.Path("/home/user/gcode_summary.txt")
SOURCE = pathlib.Path("/home/user/process_gcode.go")
DATA_DIR = pathlib.Path("/home/user/projects/cnc_data")
BINARY = pathlib.Path("/tmp/process_gcode_test")


def test_gcode_summary_exists():
    """Check if the gcode_summary.txt file exists."""
    file_path = "/home/user/gcode_summary.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. The Go program must generate this file."


def test_gcode_summary_content():
    """Check if the gcode_summary.txt file contains the correct output."""
    file_path = "/home/user/gcode_summary.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    expected_lines = [
        "bracket.gcode: 4",
        "gear.gcode: 3",
        "spacer.gcode: 0"
    ]

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Contents of {file_path} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_go_program_exists():
    """Check if the Go source file exists."""
    file_path = "/home/user/process_gcode.go"
    assert os.path.isfile(file_path), f"The Go program {file_path} is missing."


def compress_rle(data):
    result = bytearray()
    i = 0
    while i < len(data):
        count = 1
        while i + count < len(data) and data[i + count] == data[i] and count < 255:
            count += 1
        result.extend((count, data[i]))
        i += count
    return bytes(result)


def expected_summary(fixtures):
    lines = []
    for filename in sorted(fixtures):
        count = 0
        for line in fixtures[filename].splitlines():
            fields = line.split()
            if fields and fields[0] == "G1":
                count += 1
        output_name = pathlib.Path(filename).stem + ".gcode"
        lines.append(f"{output_name}: {count}")
    return lines


def read_summary_lines():
    assert SUMMARY.is_file(), "The compiled program did not create gcode_summary.txt"
    return [line.strip() for line in SUMMARY.read_text(encoding="utf-8").splitlines() if line.strip()]


def run_binary():
    if SUMMARY.exists():
        SUMMARY.unlink()
    completed = subprocess.run(
        [str(BINARY)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f"Compiled Go program exited with {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )


def test_go_program_compiles_runs_and_processes_derived_inputs():
    build = subprocess.run(
        ["go", "build", "-o", str(BINARY), str(SOURCE)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, (
        f"process_gcode.go does not compile.\nstdout:\n{build.stdout}\nstderr:\n{build.stderr}"
    )
    assert BINARY.is_file(), "go build did not produce an executable"

    original_expected = [
        "bracket.gcode: 4",
        "gear.gcode: 3",
        "spacer.gcode: 0",
    ]
    run_binary()
    assert read_summary_lines() == original_expected, (
        "Running the compiled program on the supplied CNC files did not produce the expected summary"
    )

    fixtures = {
        "alpha.rle": (
            "G21 ; Unicode test: café Ω\n"
            "   G1 X1 Y1\n"
            "G10 X2\n"
            "A" * 300 + "\n"
            "G1X3 Y3\n"
        ),
        "middle.rle": (
            "\tG1\tZ2.5\n"
            "  ; G1 X99\n"
            "g1 X4\n"
            "G0 X0\n"
        ),
        "zeta.rle": (
            "G90\n"
            "G1 X0\n"
            "  G1 Y0 ; move\n"
            "G100 X5\n"
            "\tG1\n"
        ),
    }
    expected = expected_summary(fixtures)

    with tempfile.TemporaryDirectory() as backup_dir:
        backup = pathlib.Path(backup_dir)
        original_rle = list(DATA_DIR.glob("*.rle"))
        for path in original_rle:
            shutil.move(str(path), str(backup / path.name))

        ignored = DATA_DIR / "ignored.bin"
        try:
            for filename, text in fixtures.items():
                encoded = text.encode("utf-16le")
                (DATA_DIR / filename).write_bytes(compress_rle(encoded))
            ignored.write_bytes(b"not an RLE GCode file")

            run_binary()
            actual = read_summary_lines()
            assert actual == expected, (
                "The compiled program did not correctly process derived RLE/UTF-16LE inputs, "
                "filter commands, and sort filenames.\n"
                f"Expected: {expected}\nActual: {actual}"
            )
        finally:
            for path in DATA_DIR.glob("*.rle"):
                path.unlink()
            if ignored.exists():
                ignored.unlink()
            for path in backup.glob("*.rle"):
                shutil.move(str(path), str(DATA_DIR / path.name))
            try:
                run_binary()
            except Exception:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
