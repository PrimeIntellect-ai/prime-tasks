#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import re
import secrets
import stat
import subprocess
import uuid
import zipfile

BACKUP_DIR = "/home/user/backups"
SCRIPT = "/home/user/find_bloat.py"
OUTPUT = "/home/user/largest_backups.txt"


def derive_expected():
    results = []
    for zf_path in glob.glob(os.path.join(BACKUP_DIR, "*.zip")):
        if not zipfile.is_zipfile(zf_path):
            continue
        try:
            with zipfile.ZipFile(zf_path, "r") as zf:
                infolist = zf.infolist()
                if not infolist:
                    continue
                results.append((zf_path, max(info.file_size for info in infolist)))
        except (OSError, zipfile.BadZipFile):
            continue
    results.sort(key=lambda x: x[1], reverse=True)
    return results


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_largest_backups_output():
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."

    expected_lines = [f"{path}: {size}" for path, size in derive_expected()]
    actual_lines = read_nonempty_lines(OUTPUT)

    assert len(actual_lines) == len(expected_lines), (
        f"Output file has {len(actual_lines)} lines, expected {len(expected_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch.\n"
            f"Expected: '{expected}'\n"
            f"Actual:   '{actual}'"
        )


def test_find_bloat_script_on_unseen_archives():
    assert os.path.lexists(SCRIPT), f"Required script {SCRIPT} does not exist."
    assert not os.path.islink(SCRIPT), f"{SCRIPT} must be a regular Python script, not a symlink."
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT} is not a regular file."

    subprocess.run(
        ["python3", "-m", "py_compile", SCRIPT],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )

    token = uuid.uuid4().hex
    valid_one = os.path.join(BACKUP_DIR, f"audit_{token}_one.zip")
    valid_two = os.path.join(BACKUP_DIR, f"audit_{token}_two.zip")
    corrupt = os.path.join(BACKUP_DIR, f"audit_{token}_corrupt.zip")
    created = [valid_one, valid_two, corrupt]

    size_one_small = 1000 + secrets.randbelow(4000)
    size_one_large = 43000 + secrets.randbelow(5000)
    size_two = 50000 + secrets.randbelow(5000)

    try:
        with zipfile.ZipFile(valid_one, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("small.bin", b"a" * size_one_small)
            zf.writestr("largest.bin", b"b" * size_one_large)
        with zipfile.ZipFile(valid_two, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("nested/data.bin", b"c" * size_two)
        with open(corrupt, "wb") as f:
            f.write(b"PK\x00\x00 verifier-generated corrupt archive " + secrets.token_bytes(24))

        expected = dict(derive_expected())
        proc = subprocess.run(
            ["python3", SCRIPT],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
            cwd="/tmp",
        )
        assert proc.returncode == 0, (
            f"{SCRIPT} exited with status {proc.returncode}. stderr:\n{proc.stderr}"
        )

        lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        parsed = {}
        pattern = re.compile(r"^(/home/user/backups/[^:\n]+\.zip): ([0-9]+)$")
        for line in lines:
            match = pattern.fullmatch(line)
            assert match, f"Script emitted a line in the wrong format: {line!r}"
            path, size = match.group(1), int(match.group(2))
            assert path not in parsed, f"Script emitted duplicate output for {path}."
            parsed[path] = size

        assert parsed == expected, (
            "Script output did not match archive-header-derived results for the "
            f"unseen archives. Expected {expected!r}, got {parsed!r}."
        )
        assert corrupt not in parsed, "Corrupted zip was not skipped."
    finally:
        for path in created:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_script_sort_pipeline_reproduces_saved_output():
    proc = subprocess.run(
        [
            "bash",
            "-c",
            "set -o pipefail; python3 /home/user/find_bloat.py | LC_ALL=C sort -t: -k2,2nr",
        ],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
        cwd="/home/user",
    )
    assert proc.returncode == 0, f"Script/sort pipeline failed:\n{proc.stderr}"
    pipeline_lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    assert pipeline_lines == read_nonempty_lines(OUTPUT), (
        "Piping find_bloat.py through descending numeric sort does not reproduce "
        "/home/user/largest_backups.txt."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
