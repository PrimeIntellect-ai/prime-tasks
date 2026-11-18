#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess

ARCHIVE_PATH = "/home/user/archive/backup.tar.zst"
ID_SUM_PATH = "/home/user/id_sum.txt"
CLEANED_DATA_PATH = "/home/user/cleaned_data.csv"
SCRIPT_PATH = "/home/user/clean.sh"
RAW_PATH = "/home/user/raw_data.csv"


def original_raw():
    lines = ["ID,SensorA,SensorB,SensorC"]
    for i in range(1, 1001):
        ident = 9000000000000000000 + i
        sa = "NaN" if i % 10 == 0 else f"1.{i}"
        lines.append(f"{ident},{sa},NaN,2.{i}")
    return "\n".join(lines) + "\n"


def original_cleaned():
    lines = ["ID,SensorA,SensorC"]
    for i in range(1, 1001):
        ident = 9000000000000000000 + i
        sa = "0.0" if i % 10 == 0 else f"1.{i}"
        lines.append(f"{ident},{sa},2.{i}")
    return "\n".join(lines) + "\n"


def archive_member_and_data(path):
    subprocess.run(["zstd", "-q", "-t", path], check=True, timeout=15)
    listing = subprocess.run(
        ["tar", "--zstd", "-tf", path],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15,
    ).stdout.splitlines()
    matches = [name for name in listing if os.path.basename(name.rstrip("/")) == "raw_data.csv"]
    assert len(matches) == 1, f"Archive must contain exactly one raw_data.csv; members were {listing!r}"
    result = subprocess.run(
        ["tar", "--zstd", "-xOf", path, matches[0]],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15,
    )
    return result.stdout


def test_clean_script_exists_is_executable_and_uses_allowed_runtime():
    assert os.path.isfile(SCRIPT_PATH), f"Cleaning script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Cleaning script is not executable: {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.match(r"^#!\s*(?:/usr/bin/env\s+)?(?:/bin/|/usr/bin/)?bash(?:\s|$)", first_line), \
        "clean.sh must be a Bash script"
    code = "\n".join(line.split("#", 1)[0] for line in source.splitlines()[1:])
    forbidden = re.compile(
        r"(?im)(?:^|[;&|()]\s*|\b(?:sudo|env|command|exec|xargs)\s+)"
        r"(?:/[^\s;&|()]+/)?(?:python[0-9.]*|perl|ruby|Rscript|R)(?=\s|$)"
    )
    assert not forbidden.search(code), "clean.sh invokes a forbidden language runtime"
    subprocess.run(["bash", "-n", SCRIPT_PATH], check=True, timeout=10)


def test_archive_exists_and_is_valid_original_backup():
    assert os.path.isfile(ARCHIVE_PATH), f"Archive not found at {ARCHIVE_PATH}"
    assert archive_member_and_data(ARCHIVE_PATH) == original_raw().encode(), \
        "Archive is not a valid backup of the original raw_data.csv"


def test_id_sum_correct():
    assert os.path.isfile(ID_SUM_PATH), f"ID sum file not found at {ID_SUM_PATH}"
    with open(ID_SUM_PATH, "r") as f:
        actual_sum = f.read().strip()
    expected_sum = "9000000000000000500500"
    assert actual_sum == expected_sum, f"Sum mismatch: Expected {expected_sum}, got {actual_sum}"
    assert open(ID_SUM_PATH, "rb").read() == (expected_sum + "\n").encode(), \
        "id_sum.txt must contain only the exact integer sum and one newline"


def test_cleaned_data_exists():
    assert os.path.isfile(CLEANED_DATA_PATH), f"Cleaned data not found at {CLEANED_DATA_PATH}"


def test_cleaned_data_columns():
    with open(CLEANED_DATA_PATH, "r") as f:
        header = f.readline().strip()
    expected_header = "ID,SensorA,SensorC"
    assert header == expected_header, \
        f"Incorrect columns in cleaned data. Expected header '{expected_header}', got '{header}'"


def test_cleaned_data_imputation_and_full_contents():
    with open(CLEANED_DATA_PATH, "r") as f:
        contents = f.read()
    lines = contents.splitlines()
    assert len(lines) == 1001, f"Expected 1001 lines in {CLEANED_DATA_PATH}, found {len(lines)}"
    for i, line in enumerate(lines):
        assert "NaN" not in line, f"Found 'NaN' in cleaned data at line {i + 1}: {line}"
    row_10 = lines[10].split(',')
    assert row_10[1] == "0.0", f"Expected '0.0' for SensorA at row 10, got {row_10[1]}"
    assert contents == original_cleaned(), "cleaned_data.csv does not preserve and transform every input row correctly"


def test_script_dynamically_processes_unseen_layout_and_values():
    rng = random.Random(secrets.randbits(128))
    headers = ["ID"] + [f"Probe_{secrets.token_hex(4)}" for _ in range(6)]
    all_nan = set(rng.sample(range(1, 7), 2))
    offsets = {col: rng.randrange(1, 22) for col in range(1, 7) if col not in all_nan}
    raw_rows = []
    expected_rows = []
    ids = []

    for row in range(1, 24):
        ident = 8100000000000000000 + secrets.randbelow(100000000000000000)
        ids.append(ident)
        raw = [str(ident)]
        cleaned = [str(ident)]
        for col in range(1, 7):
            if col in all_nan:
                raw.append("NaN")
            elif (row + offsets[col]) % 5 == 0:
                raw.append("NaN")
                cleaned.append("0.0")
            else:
                value = f"{col * 17 + row}.{secrets.randbelow(1000000):06d}"
                raw.append(value)
                cleaned.append(value)
        raw_rows.append(raw)
        expected_rows.append(cleaned)

    kept_headers = [name for i, name in enumerate(headers) if i not in all_nan]
    raw_text = "\n".join([",".join(headers)] + [",".join(r) for r in raw_rows]) + "\n"
    expected_text = "\n".join([",".join(kept_headers)] + [",".join(r) for r in expected_rows]) + "\n"
    with open(RAW_PATH, "w", newline="") as f:
        f.write(raw_text)

    subprocess.run([SCRIPT_PATH], cwd="/home/user", check=True, timeout=30)

    assert os.path.isfile(ARCHIVE_PATH), "Script did not create the archive when executed"
    assert archive_member_and_data(ARCHIVE_PATH) == raw_text.encode(), \
        "Archive created by clean.sh is not an exact backup of its input"
    assert os.path.isfile(CLEANED_DATA_PATH), "Script did not create cleaned_data.csv"
    with open(CLEANED_DATA_PATH, "r", newline="") as f:
        actual_cleaned = f.read()
    assert actual_cleaned == expected_text, \
        "Script failed to dynamically drop all-NaN columns, impute NaNs, or preserve input values"
    expected_sum = str(sum(ids)) + "\n"
    assert os.path.isfile(ID_SUM_PATH), "Script did not create id_sum.txt"
    with open(ID_SUM_PATH, "r", newline="") as f:
        actual_sum = f.read()
    assert actual_sum == expected_sum, \
        f"Precision-lossless dynamic ID sum mismatch: expected {expected_sum!r}, got {actual_sum!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
