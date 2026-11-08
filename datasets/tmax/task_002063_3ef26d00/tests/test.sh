#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
import secrets

GCODE_1_CONTENT = """G21 ; Set units to millimeters
G90 ; Use absolute coordinates
G1 X10 Y10 F1000
G1 Z0.5
G1 E5 F300
"""

GCODE_2_CONTENT = """M104 S200 ; Set extruder temp
M140 S60 ; Set bed temp
G28 ; Home all axes
G1 X100.5 Y100.5 Z10 F2000
"""

LOG_PATH = "/home/user/storage/server.log"
OUTPUT_DIR = "/home/user/extracted_gcode"


def encode_hex_rle(text):
    encoded = []
    i = 0
    while i < len(text):
        count = 1
        while i + count < len(text) and text[i + count] == text[i] and count < 255:
            count += 1
        encoded.append(f"{count:02x}{ord(text[i]):02x}")
        i += count
    return "".join(encoded)


def clear_output_directory():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    for name in os.listdir(OUTPUT_DIR):
        path = os.path.join(OUTPUT_DIR, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


def find_candidate_scripts():
    candidates = []
    seen = set()
    roots = ["/home/user", "/tmp", "/root", "/workspace", "/app"]

    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, dirnames, filenames in os.walk(root):
            dirnames[:] = [
                name for name in dirnames
                if name not in {".cache", "__pycache__", "site-packages", "extracted_gcode", "storage"}
            ]
            for filename in filenames:
                if not filename.endswith(".py"):
                    continue
                path = os.path.realpath(os.path.join(directory, filename))
                if path == "/tmp/test_final_state.py" or path in seen:
                    continue
                seen.add(path)
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
                        source = handle.read()
                except OSError:
                    continue

                # All Python files in the task's home are eligible. Outside it,
                # only consider scripts that clearly target this task.
                if path.startswith("/home/user/") or "server.log" in source or "ARCHIVED GCODE" in source:
                    candidates.append(path)
    return candidates


def run_script(path, cwd):
    try:
        result = subprocess.run(
            ["python3", path],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
        return result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def test_python_extraction_script_exists_and_works():
    scripts = find_candidate_scripts()
    assert scripts, "No Python extraction script was found."

    with open(LOG_PATH, "rb") as handle:
        original_log = handle.read()

    token = secrets.token_hex(12)
    probe_filename = f"verification_{token}.gcode"
    probe_content = f"G1 X{token[:4]} Y{token[4:8]}\nM117 AAAA-{token}\n"
    payload = encode_hex_rle(probe_content)
    wrapped = "\n".join(payload[i:i + 37] for i in range(0, len(payload), 37))
    probe_log = (
        "[2099-01-01 00:00:00] INFO verifier probe\n"
        f"=== BEGIN ARCHIVED GCODE: {probe_filename} ===\n"
        f"{wrapped}\n"
        "=== END ARCHIVED GCODE ===\n"
    ).encode("ascii")

    working_script = None
    working_cwd = None
    try:
        for script in scripts:
            for cwd in dict.fromkeys(["/home/user", os.path.dirname(script)]):
                with open(LOG_PATH, "wb") as handle:
                    handle.write(probe_log)
                clear_output_directory()
                if not run_script(script, cwd):
                    continue
                probe_path = os.path.join(OUTPUT_DIR, probe_filename)
                try:
                    with open(probe_path, "r", encoding="utf-8") as handle:
                        actual = handle.read()
                except OSError:
                    continue
                if actual == probe_content:
                    working_script = script
                    working_cwd = cwd
                    break
            if working_script is not None:
                break
    finally:
        with open(LOG_PATH, "wb") as handle:
            handle.write(original_log)

    assert working_script is not None, (
        "No submitted Python script successfully parsed and decompressed a generated log block."
    )

    clear_output_directory()
    assert run_script(working_script, working_cwd), "The extraction script failed on server.log."


def test_extracted_gcode_directory_exists():
    """Verify that the extracted_gcode directory exists."""
    path = "/home/user/extracted_gcode"
    assert os.path.isdir(path), f"Directory {path} does not exist."


def test_part_base_gcode_content():
    """Verify that part_base.gcode was extracted and decompressed correctly."""
    path = "/home/user/extracted_gcode/part_base.gcode"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert content == GCODE_1_CONTENT, f"Content of {path} does not match expected output."


def test_heated_bed_init_gcode_content():
    """Verify that heated_bed_init.gcode was extracted and decompressed correctly."""
    path = "/home/user/extracted_gcode/heated_bed_init.gcode"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert content == GCODE_2_CONTENT, f"Content of {path} does not match expected output."


def test_tarball_exists_and_valid():
    """Verify that the tarball exists and contains the correct files and contents."""
    tar_path = "/home/user/gcode_archive.tar.gz"
    assert os.path.isfile(tar_path), f"Archive {tar_path} does not exist."
    assert tarfile.is_tarfile(tar_path), f"Archive {tar_path} is not a valid tar file."

    expected = {
        "part_base.gcode": GCODE_1_CONTENT.encode("utf-8"),
        "heated_bed_init.gcode": GCODE_2_CONTENT.encode("utf-8"),
    }

    with tarfile.open(tar_path, "r:gz") as tar:
        names = tar.getnames()
        basenames = [os.path.basename(name) for name in names]
        assert "part_base.gcode" in basenames, "part_base.gcode is missing from the tar archive."
        assert "heated_bed_init.gcode" in basenames, "heated_bed_init.gcode is missing from the tar archive."

        for basename, expected_bytes in expected.items():
            matches = [member for member in tar.getmembers() if os.path.basename(member.name) == basename]
            assert len(matches) == 1, f"Archive must contain exactly one {basename} entry."
            member = matches[0]
            assert member.isfile(), f"Archive entry {member.name} is not a regular file."
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive entry {member.name}."
            archived_bytes = extracted.read()
            assert archived_bytes == expected_bytes, f"Content of {basename} in the archive is incorrect."

            disk_path = os.path.join(OUTPUT_DIR, basename)
            with open(disk_path, "rb") as handle:
                assert archived_bytes == handle.read(), f"Archive entry {basename} does not match the extracted file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
