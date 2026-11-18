#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/scan_dataset.sh"
INVENTORY_PATH = "/home/user/dataset_inventory.txt"
DATASET_ROOT = "/home/user/dataset"


def read_inventory():
    assert os.path.isfile(INVENTORY_PATH), f"The output file {INVENTORY_PATH} does not exist."
    with open(INVENTORY_PATH, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def classify(path):
    with open(path, "rb") as f:
        header = f.read(8)
    if header.startswith(b"\x7fELF"):
        return "ELF"
    if header.startswith(b"\x37\x7f\x06\x82") or header.startswith(b"\x37\x7f\x06\x83"):
        return "WAL"
    if header.startswith(b";FLAVOR:"):
        return "GCODE"
    return "UNKNOWN"


def derive_expected():
    lines = []
    for directory, dirnames, filenames in os.walk(DATASET_ROOT, followlinks=False):
        dirnames[:] = [
            name for name in dirnames
            if not os.path.islink(os.path.join(directory, name))
        ]
        for name in filenames:
            path = os.path.join(directory, name)
            if os.path.islink(path):
                continue
            mode = os.stat(path, follow_symlinks=False).st_mode
            if stat.S_ISREG(mode):
                lines.append(f"{path}: {classify(path)}")
    return sorted(lines)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    subprocess.run(["bash", "-n", SCRIPT_PATH], check=True, timeout=5)


def test_inventory_exists_and_correct():
    expected_lines = [
        "/home/user/dataset/binary_tool: ELF",
        "/home/user/dataset/exp_a/broken.gcode: UNKNOWN",
        "/home/user/dataset/exp_a/cache.wal: WAL",
        "/home/user/dataset/exp_a/helper_bin: ELF",
        "/home/user/dataset/exp_b/db.wal: WAL",
        "/home/user/dataset/exp_b/empty.dat: UNKNOWN",
        "/home/user/dataset/exp_b/nested/print_2.gcode: GCODE",
        "/home/user/dataset/notes.txt: UNKNOWN",
        "/home/user/dataset/print_1.gcode: GCODE"
    ]
    actual_lines = read_inventory()
    assert actual_lines == expected_lines, (
        f"The contents of {INVENTORY_PATH} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_script_executes_and_handles_new_files_and_symlinks_safely():
    dynamic = os.path.join(DATASET_ROOT, "verification additions")
    nested = os.path.join(dynamic, "nested")
    os.makedirs(nested, exist_ok=True)

    samples = {
        os.path.join(dynamic, "elf-short.bin"): b"\x7fELF",
        os.path.join(dynamic, "wal-83.bin"): b"\x37\x7f\x06\x83extra",
        os.path.join(dynamic, "exact.gcode"): b";FLAVOR:",
        os.path.join(dynamic, "leading-byte.gcode"): b"\xef\xbb\xbf;FLAVOR:Marlin\n",
        os.path.join(nested, "ordinary file.txt"): b"plain text\n",
    }
    for path, contents in samples.items():
        with open(path, "wb") as f:
            f.write(contents)

    marker = "/tmp/scan_dataset_execution_marker"
    if os.path.lexists(marker):
        os.unlink(marker)
    executable_data = os.path.join(dynamic, "do-not-execute")
    with open(executable_data, "w", encoding="utf-8") as f:
        f.write(f"#!/bin/sh\nprintf executed > {marker}\n")
    os.chmod(executable_data, 0o755)

    external = tempfile.mkdtemp(prefix="dataset-verifier-external-")
    with open(os.path.join(external, "must-not-appear.bin"), "wb") as f:
        f.write(b"\x7fELFexternal")
    os.symlink(external, os.path.join(dynamic, "external-directory-link"))
    os.symlink(os.path.join(DATASET_ROOT, "binary_tool"), os.path.join(dynamic, "regular-file-link"))
    os.symlink(dynamic, os.path.join(nested, "new-cycle"))

    env = os.environ.copy()
    env["LC_ALL"] = "C"
    subprocess.run(
        ["bash", SCRIPT_PATH],
        check=True,
        timeout=10,
        cwd="/home/user",
        env=env,
    )

    assert not os.path.exists(marker), "The scanner executed a dataset file."
    expected_lines = derive_expected()
    actual_lines = read_inventory()
    assert actual_lines == expected_lines, (
        "Running scan_dataset.sh did not produce a complete, sorted, correctly "
        "classified inventory while excluding symlinks.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
