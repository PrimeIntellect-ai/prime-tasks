#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import threading
import time
import uuid


def test_malicious_file_skipped():
    assert not os.path.exists("/home/user/hacked.txt"), "Malicious file was extracted outside the intended directory!"
    assert not os.path.exists("/home/user/extracted/../hacked.txt"), "Malicious file was extracted outside the intended directory via path traversal!"


def test_valid_files_extracted():
    expected = {
        "/home/user/extracted/test1.gcode": (
            "G21 ; Set units to millimeters\n"
            "G90 ; Use absolute coordinates\n"
            "G28 ; Home all axes\n"
            "G1 Z5 F5000\n"
        ),
        "/home/user/extracted/subdir/test2.gcode": (
            "G21 ; Set units to millimeters\n"
            "G90 ; Use absolute coordinates\n"
            "G1 X10 Y20 F3000\n"
            "G1 X10 Y30\n"
        ),
        "/home/user/extracted/data/test3.gcode": (
            "G28 X Y ; Home X and Y\n"
            "G1 Z10\n"
        ),
    }
    for path, content in expected.items():
        assert os.path.isfile(path), f"Valid file {path} was not extracted correctly."
        with open(path, "r", newline="") as f:
            assert f.read() == content, f"Extracted content of {path} is incorrect."


def test_symlinks_created_and_correct():
    expected_symlinks = {
        "/home/user/organized/calibration/test1.gcode": "/home/user/extracted/test1.gcode",
        "/home/user/organized/calibration/test3.gcode": "/home/user/extracted/data/test3.gcode",
        "/home/user/organized/production/test2.gcode": "/home/user/extracted/subdir/test2.gcode",
    }
    for symlink, target in expected_symlinks.items():
        assert os.path.islink(symlink), f"Expected symlink {symlink} does not exist or is not a symlink."
        actual_target = os.readlink(symlink)
        assert actual_target == target, f"Symlink {symlink} points to {actual_target}, expected {target}."


def test_verification_log():
    log_path = "/home/user/symlink_report.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_lines = [
        "/home/user/organized/calibration/test1.gcode -> /home/user/extracted/test1.gcode",
        "/home/user/organized/calibration/test3.gcode -> /home/user/extracted/data/test3.gcode",
        "/home/user/organized/production/test2.gcode -> /home/user/extracted/subdir/test2.gcode",
    ]
    assert lines == expected_lines, f"Log file contents do not match the expected sorted format. Got: {lines}"


def test_script_executes_dynamic_archive_safely_and_atomically():
    script = "/home/user/process_dataset.sh"
    assert os.path.isfile(script), "process_dataset.sh does not exist."
    mode = os.stat(script).st_mode
    assert stat.S_ISREG(mode), "process_dataset.sh is not a regular file."
    assert mode & 0o111, "process_dataset.sh is not executable."

    token = uuid.uuid4().hex
    calibration_rel = f"cal_{token}/home_{token}.gcode"
    production_rel = f"prod_{token}/part_{token}.gcode"
    notes_rel = f"metadata_{token}/notes.txt"
    escaped_name = f"escaped_{token}.txt"
    nested_escape_name = f"nested_escape_{token}.txt"
    absolute_evil = f"/tmp/absolute_escape_{token}.txt"

    calibration_content = "G21\nG28 ; dynamic auto home\nG1 X2 Y3\n"
    # Large content makes a non-atomic direct write observably replace/truncate
    # the pre-existing destination before all bytes have been written.
    production_content = "G21\n" + ("G1 X123 Y456 F3000 ; dynamic production data\n" * 180000)
    notes_content = "dynamic sensor metadata\nserial=" + token + "\n"

    entries = [
        (calibration_rel, calibration_content),
        (production_rel, production_content),
        (notes_rel, notes_content),
        (f"../{escaped_name}", "must not escape\n"),
        (f"deep/../../{nested_escape_name}", "must not escape either\n"),
        (absolute_evil, "must not write an absolute path\n"),
    ]
    with open("/home/user/dataset.archive", "w", newline="") as archive:
        for rel, content in entries:
            archive.write("[FILE_START]\n")
            archive.write(rel + "\n")
            archive.write("[CONTENT_START]\n")
            archive.write(content)
            archive.write("[FILE_END]\n")

    shutil.rmtree("/home/user/extracted", ignore_errors=True)
    shutil.rmtree("/home/user/organized", ignore_errors=True)
    try:
        os.unlink("/home/user/symlink_report.log")
    except FileNotFoundError:
        pass

    production_path = os.path.join("/home/user/extracted", production_rel)
    os.makedirs(os.path.dirname(production_path), exist_ok=True)
    sentinel = b"OLD DESTINATION MUST REMAIN UNTIL ATOMIC REPLACE\n"
    with open(production_path, "wb") as f:
        f.write(sentinel)

    escaped_paths = [
        os.path.join("/home/user", escaped_name),
        os.path.join("/home/user", nested_escape_name),
        absolute_evil,
    ]
    for path in escaped_paths:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    expected_size = len(production_content.encode())
    allowed_sizes = {len(sentinel), expected_size}
    observations = []
    stop = threading.Event()

    def observe_destination():
        while not stop.is_set():
            try:
                size = os.stat(production_path).st_size
            except FileNotFoundError:
                observations.append("destination disappeared")
            else:
                if size not in allowed_sizes:
                    observations.append(f"partial destination size {size}")
            time.sleep(0.0005)

    watcher = threading.Thread(target=observe_destination, daemon=True)
    watcher.start()
    try:
        result = subprocess.run(
            [script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
    finally:
        stop.set()
        watcher.join(timeout=2)

    assert result.returncode == 0, (
        f"process_dataset.sh failed on a dynamic archive (exit {result.returncode}). "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert not observations, "Destination was exposed in a non-atomic state: " + "; ".join(observations[:5])

    expected_files = {
        os.path.join("/home/user/extracted", calibration_rel): calibration_content,
        production_path: production_content,
        os.path.join("/home/user/extracted", notes_rel): notes_content,
    }
    for path, expected_content in expected_files.items():
        assert os.path.isfile(path), f"Dynamic archive file was not extracted: {path}"
        with open(path, "r", newline="") as f:
            assert f.read() == expected_content, f"Incorrect dynamically extracted content: {path}"

    for path in escaped_paths:
        assert not os.path.lexists(path), f"Malicious archive path was written: {path}"

    calibration_link = f"/home/user/organized/calibration/home_{token}.gcode"
    production_link = f"/home/user/organized/production/part_{token}.gcode"
    expected_links = {
        calibration_link: os.path.join("/home/user/extracted", calibration_rel),
        production_link: production_path,
    }
    for link, target in expected_links.items():
        assert os.path.islink(link), f"Dynamic GCode symlink is missing: {link}"
        assert os.readlink(link) == target, f"Dynamic symlink {link} has the wrong target."

    wrong_calibration = f"/home/user/organized/calibration/part_{token}.gcode"
    wrong_production = f"/home/user/organized/production/home_{token}.gcode"
    assert not os.path.lexists(wrong_calibration), "Production GCode was miscategorized as calibration."
    assert not os.path.lexists(wrong_production), "Calibration GCode was miscategorized as production."

    expected_report = sorted(f"{link} -> {target}" for link, target in expected_links.items())
    with open("/home/user/symlink_report.log", "r") as f:
        actual_report = [line.strip() for line in f if line.strip()]
    assert actual_report == expected_report, f"Dynamic report is incorrect: {actual_report}"

    leftovers = []
    for root, dirs, files in os.walk("/home/user/extracted"):
        leftovers.extend(os.path.join(root, name) for name in files if name.endswith(".tmp"))
    assert not leftovers, f"Temporary extraction files were left behind: {leftovers}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
