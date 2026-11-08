#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path

RAW = Path("/home/user/raw_translations.txt")
OUTPUT = Path("/home/user/hourly_unique_translations.txt")
SOURCE = Path("/home/user/dedup.rs")
EXECUTABLE = Path("/home/user/dedup")


def expected_for(records):
    result = set()
    for record in records:
        timestamp, locale, text = record.split("|", 2)
        result.add(f"{timestamp[:13]}|{locale}|{text}")
    return sorted(result)


def make_fixture(label):
    nonce = secrets.token_hex(10)
    a = f"{label}-éclair-{nonce}"
    b = f"{label}-こんにちは-{nonce}"
    c = f"{label}-До свидания-{nonce}"
    return [
        f"2025-07-03T22:59:58Z|ja|{b}",
        f"2025-07-03T21:35:17Z|fr|{a}",
        f"2025-07-03T21:01:02Z|fr|{a}",
        f"2025-07-03T21:45:00Z|ja|{b}",
        f"2025-07-03T20:59:59Z|ru|{c}",
        f"2025-07-03T21:12:12Z|es|{a}",
        f"2025-07-03T20:02:03Z|ru|{c}",
        f"2025-07-03T22:00:01Z|ja|{b}",
    ]


def run_and_check(program, label):
    records = make_fixture(label)
    RAW.write_text("\n".join(records) + "\n", encoding="utf-8")
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()

    result = subprocess.run(
        ["runuser", "-u", "user", "--", str(program)],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{program} failed on a generated input as user: "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert OUTPUT.exists(), f"{program} did not create {OUTPUT}."
    assert OUTPUT.is_file(), f"{OUTPUT} is not a regular file after running {program}."
    actual = OUTPUT.read_text(encoding="utf-8").splitlines()
    assert actual == expected_for(records), (
        f"{program} did not correctly bucket, deduplicate, and alphabetically sort "
        "a generated Unicode fixture."
    )


def test_final_state_and_behavior():
    # Preserve the original fixed-fixture assertion.
    assert OUTPUT.exists(), f"Output file {OUTPUT} does not exist."
    assert OUTPUT.is_file(), f"{OUTPUT} is not a regular file."
    expected_content = (
        "2023-10-24T14|es|¡Hola!\n"
        "2023-10-24T14|fr|Bonjour\n"
        "2023-10-24T14|ja|こんにちは\n"
        "2023-10-24T15|es|Adiós\n"
        "2023-10-24T15|ja|さようなら\n"
    )
    content = OUTPUT.read_text(encoding="utf-8")
    assert content.strip() == expected_content.strip(), (
        "The contents of the output file do not match the expected deduplicated "
        "and sorted output."
    )

    # Preserve the original executable assertions and require a native compiled artifact.
    assert EXECUTABLE.exists(), f"Compiled executable {EXECUTABLE} does not exist."
    assert EXECUTABLE.is_file(), f"{EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with EXECUTABLE.open("rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a native compiled executable."

    # The requested Rust source must exist and independently compile.
    assert SOURCE.exists(), f"Rust source file {SOURCE} does not exist."
    assert SOURCE.is_file(), f"{SOURCE} is not a regular file."

    # Preserve the original crontab assertion.
    try:
        result = subprocess.run(
            ["crontab", "-u", "user", "-l"],
            capture_output=True,
            text=True,
            check=True,
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        assert False, "Failed to read crontab for 'user'. Ensure the crontab exists."
    expected_cron_job = "0 * * * * /home/user/dedup"
    found = any(expected_cron_job in line for line in crontab_content.splitlines())
    assert found, f"Crontab for 'user' does not contain the expected job: {expected_cron_job}"

    raw_bytes = RAW.read_bytes()
    output_bytes = OUTPUT.read_bytes()
    raw_stat = RAW.stat()
    output_stat = OUTPUT.stat()
    moved_executable = None

    try:
        with tempfile.TemporaryDirectory(prefix="dedup-verify-") as temp_dir:
            os.chmod(temp_dir, 0o755)
            rebuilt = Path(temp_dir) / "dedup_from_source"
            compile_result = subprocess.run(
                ["rustc", str(SOURCE), "-O", "-o", str(rebuilt)],
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert compile_result.returncode == 0, (
                f"{SOURCE} does not compile successfully: {compile_result.stderr}"
            )
            assert rebuilt.is_file() and os.access(rebuilt, os.X_OK), (
                "Compiling dedup.rs did not produce an executable."
            )

            # Hide the submitted executable while exercising the freshly compiled source,
            # so the source cannot merely delegate the required work to /home/user/dedup.
            moved_executable = Path(temp_dir) / "submitted_dedup"
            os.replace(EXECUTABLE, moved_executable)
            run_and_check(rebuilt, "rebuilt")
            os.replace(moved_executable, EXECUTABLE)
            moved_executable = None

            # Independently exercise the submitted executable on another generated input.
            run_and_check(EXECUTABLE, "submitted")
    finally:
        if moved_executable is not None and moved_executable.exists() and not EXECUTABLE.exists():
            os.replace(moved_executable, EXECUTABLE)
        RAW.write_bytes(raw_bytes)
        os.chmod(RAW, stat.S_IMODE(raw_stat.st_mode))
        os.chown(RAW, raw_stat.st_uid, raw_stat.st_gid)
        OUTPUT.write_bytes(output_bytes)
        os.chmod(OUTPUT, stat.S_IMODE(output_stat.st_mode))
        os.chown(OUTPUT, output_stat.st_uid, output_stat.st_gid)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
