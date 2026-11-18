#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import tarfile
import tempfile
import subprocess
import zipfile
from pathlib import Path

RAW_DATA_DIR = "/home/user/raw_data"
SCALED_DATA_DIR = "/home/user/scaled_data"
ZIP_PATH = "/home/user/final_project.zip"
WAL_LOG_PATH = "/home/user/process_wal.log"
SCALER_SOURCE = "/home/user/scaler.c"
SCALER_BINARY = "/home/user/scaler"
RUN_SCRIPT = "/home/user/run.sh"
TOLERANCE = 0.005

COORD_RE = re.compile(r'([XYZ])([-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))')


def blueprint_scale():
    text = subprocess.check_output(
        ["tesseract", "/app/blueprint.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    match = re.search(r"SCALE\s*:\s*([-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))", text, re.I)
    assert match, "Could not OCR a SCALE value from blueprint.png"
    return float(match.group(1))


SCALE_FACTOR = blueprint_scale()


def is_valid_gcode(path):
    if not path.name.endswith(".gcode"):
        return False
    try:
        with path.open("r", encoding="utf-8") as handle:
            return any("; TYPE: PART" in handle.readline() for _ in range(5))
    except Exception:
        return False


def get_valid_gcode_files(root=RAW_DATA_DIR):
    root = Path(root)
    if not root.is_dir():
        return []
    return sorted((p for p in root.rglob("*") if p.is_file() and is_valid_gcode(p)), key=str)


def expected_archive_files(tmpdir):
    with tarfile.open("/app/data.tar.gz", "r:gz") as archive:
        archive.extractall(tmpdir)
    archive_root = Path(tmpdir) / "raw_data"
    return archive_root, get_valid_gcode_files(archive_root)


def parse_coordinates(line):
    coords = {}
    for match in COORD_RE.finditer(line):
        coords[match.group(1)] = float(match.group(2))
    return coords


def transformed_text(text, factor):
    def replace(match):
        return f"{match.group(1)}{float(match.group(2)) * factor:.3f}"
    return COORD_RE.sub(replace, text)


def read_wal():
    assert os.path.isfile(WAL_LOG_PATH), f"WAL log not found at {WAL_LOG_PATH}"
    with open(WAL_LOG_PATH, "r", encoding="utf-8") as handle:
        lines = [line.strip() for line in handle if line.strip()]
    basenames = []
    for line in lines:
        assert line.startswith("PROCESSED: "), f"Invalid log line format: {line}"
        basenames.append(line.replace("PROCESSED: ", "", 1).strip())
    return basenames


def assert_outputs_in_directory(directory, originals, factor):
    directory = Path(directory)
    assert directory.is_dir(), f"Missing output directory {directory}"
    expected_names = {p.name for p in originals}
    actual_files = {p.name for p in directory.iterdir() if p.is_file()}
    assert actual_files == expected_names, f"Output files differ: expected {expected_names}, found {actual_files}"
    assert not any(p.is_dir() for p in directory.iterdir()), "scaled_data contains nested directories"
    for original in originals:
        actual = (directory / original.name).read_text(encoding="utf-8")
        source = original.read_text(encoding="utf-8")
        assert actual == transformed_text(source, factor), (
            f"Incorrect content or formatting in {original.name}; non-coordinate text and parameters "
            "must be unchanged and XYZ coordinates must have exactly three decimals"
        )


def test_required_artifacts_and_source():
    assert os.path.isfile(SCALER_SOURCE), "Missing /home/user/scaler.c"
    assert os.path.isfile(SCALER_BINARY), "Missing /home/user/scaler"
    assert os.path.isfile(RUN_SCRIPT), "Missing /home/user/run.sh"
    assert os.access(SCALER_BINARY, os.X_OK), "scaler is not executable"
    assert os.access(RUN_SCRIPT, os.X_OK), "run.sh is not executable"

    with open(SCALER_BINARY, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "scaler must be a compiled native program"

    source = Path(SCALER_SOURCE).read_text(encoding="utf-8", errors="replace")
    uses_flock = re.search(r"\bflock\s*\(", source) and "LOCK_EX" in source
    uses_fcntl = re.search(r"\bfcntl\s*\(", source) and "F_WRLCK" in source and re.search(r"F_SETLK(?:W)?", source)
    assert uses_flock or uses_fcntl, "scaler.c does not acquire a POSIX exclusive file lock"
    assert WAL_LOG_PATH in source, "scaler.c does not reference the required shared WAL path"

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "scaler-from-source")
        subprocess.run(
            ["gcc", "-std=c11", "-pthread", SCALER_SOURCE, "-o", rebuilt, "-lm"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert os.path.isfile(rebuilt), "scaler.c did not compile as C source"

    script = Path(RUN_SCRIPT).read_text(encoding="utf-8", errors="replace")
    assert "scaler" in script, "run.sh does not invoke scaler"
    xargs_parallel = re.search(r"\bxargs\b[^\n]*\s-P\s*(?:[2-9]|[1-9][0-9]+)\b", script)
    background_parallel = re.search(r"(?<!&)&(?!&)", script) and re.search(r"\bwait\b", script)
    assert xargs_parallel or background_parallel, "run.sh does not implement concurrent execution"


def test_extraction_matches_archive():
    assert os.path.isdir(RAW_DATA_DIR), f"Raw data directory not found at {RAW_DATA_DIR}"
    with tempfile.TemporaryDirectory() as td:
        archive_root, archive_valid = expected_archive_files(td)
        for archived in (p for p in archive_root.rglob("*") if p.is_file()):
            relative = archived.relative_to(archive_root)
            extracted = Path(RAW_DATA_DIR) / relative
            assert extracted.is_file(), f"Extracted archive file is missing: {relative}"
            assert extracted.read_bytes() == archived.read_bytes(), f"Extracted file was altered: {relative}"
        actual_valid = get_valid_gcode_files()
        assert {p.relative_to(RAW_DATA_DIR) for p in actual_valid} == {
            p.relative_to(archive_root) for p in archive_valid
        }, "Valid GCode selection does not match the supplied archive"


def test_final_project_zip_and_original_assertions():
    assert os.path.isfile(ZIP_PATH), f"Final project zip not found at {ZIP_PATH}"
    valid_files = get_valid_gcode_files()
    assert len(valid_files) > 0, "No valid GCode files found in raw_data to test against."
    expected_names = {p.name for p in valid_files}

    with zipfile.ZipFile(ZIP_PATH, "r") as archive:
        names = archive.namelist()
        assert all(not name.endswith("/") for name in names), "ZIP contains directory entries"
        assert all("/" not in name.rstrip("/") and "\\" not in name for name in names), "ZIP contains nested paths"
        assert len(names) == len(set(names)), "ZIP contains duplicate entries"
        assert set(names) == expected_names, f"ZIP entries differ from expected files: {names}"

        max_error = 0.0
        for original in valid_files:
            original_text = original.read_text(encoding="utf-8")
            student_text = archive.read(original.name).decode("utf-8")
            original_lines = original_text.splitlines(keepends=True)
            student_lines = student_text.splitlines(keepends=True)
            assert len(original_lines) == len(student_lines), f"Line count mismatch in {original.name}"
            assert student_text == transformed_text(original_text, SCALE_FACTOR), (
                f"Incorrect content or formatting in {original.name}"
            )
            for line_number, (orig_line, stud_line) in enumerate(zip(original_lines, student_lines), 1):
                orig_coords = parse_coordinates(orig_line)
                stud_coords = parse_coordinates(stud_line)
                for axis, value in orig_coords.items():
                    assert axis in stud_coords, f"Missing {axis} coordinate in {original.name} line {line_number}"
                    max_error = max(max_error, abs(value * SCALE_FACTOR - stud_coords[axis]))
        assert max_error <= TOLERANCE, f"Max absolute error {max_error} exceeds tolerance {TOLERANCE}"

    expected_basenames = {p.name for p in valid_files}
    log_basenames = read_wal()
    assert len(log_basenames) == len(expected_basenames), (
        f"Expected {len(expected_basenames)} log entries, found {len(log_basenames)}."
    )
    assert set(log_basenames) == expected_basenames, "Log entries do not match expected valid GCode files."


def test_run_script_actually_processes_valid_files():
    valid_files = get_valid_gcode_files()
    if os.path.isdir(SCALED_DATA_DIR):
        subprocess.run(["rm", "-rf", SCALED_DATA_DIR], check=True)
    Path(WAL_LOG_PATH).write_bytes(b"")
    subprocess.run(
        [RUN_SCRIPT],
        cwd="/home/user",
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert_outputs_in_directory(SCALED_DATA_DIR, valid_files, SCALE_FACTOR)
    entries = read_wal()
    assert len(entries) == len(valid_files), "run.sh did not produce exactly one WAL entry per valid file"
    assert set(entries) == {p.name for p in valid_files}, "run.sh processed the wrong set of files"


def test_scaler_on_derived_concurrent_inputs():
    old_wal = Path(WAL_LOG_PATH).read_bytes() if os.path.exists(WAL_LOG_PATH) else None
    try:
        Path(WAL_LOG_PATH).write_bytes(b"")
        with tempfile.TemporaryDirectory() as td:
            processes = []
            cases = []
            for index in range(12):
                factor = 1.25 + (index % 4) * 0.25
                x = index * 2.0 - 9.0
                y = index + 0.5
                z = (index % 5) * 1.2
                text = (
                    "; TYPE: PART\n"
                    f"G1 X{x:.2f} Y{y:.2f} Z{z:.2f} E{3.5 + index:.2f} F1200\n"
                    f"G0 X{-x:.2f} Y{-y:.2f} ; unchanged comment {index}\n"
                    "M104 S200\n"
                )
                input_path = os.path.join(td, f"case_{index}.gcode")
                output_path = os.path.join(td, f"out_{index}.gcode")
                Path(input_path).write_text(text, encoding="utf-8")
                process = subprocess.Popen(
                    [SCALER_BINARY, input_path, output_path, str(factor)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                processes.append(process)
                cases.append((input_path, output_path, text, factor))

            for process in processes:
                stdout, stderr = process.communicate(timeout=20)
                assert process.returncode == 0, f"scaler failed: {stderr.decode(errors='replace')}"

            for input_path, output_path, text, factor in cases:
                assert os.path.isfile(output_path), f"scaler did not create {output_path}"
                actual = Path(output_path).read_text(encoding="utf-8")
                assert actual == transformed_text(text, factor), (
                    f"scaler produced incorrect text for {os.path.basename(input_path)}"
                )

            entries = read_wal()
            expected = {os.path.basename(case[0]) for case in cases}
            assert len(entries) == len(cases), "Concurrent scaler executions lost or corrupted WAL entries"
            assert set(entries) == expected, "Concurrent scaler WAL entries have incorrect basenames"
    finally:
        if old_wal is None:
            try:
                os.remove(WAL_LOG_PATH)
            except FileNotFoundError:
                pass
        else:
            Path(WAL_LOG_PATH).write_bytes(old_wal)


def main():
    test_required_artifacts_and_source()
    test_extraction_matches_archive()
    test_final_project_zip_and_original_assertions()
    test_run_script_actually_processes_valid_files()
    test_scaler_on_derived_concurrent_inputs()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
