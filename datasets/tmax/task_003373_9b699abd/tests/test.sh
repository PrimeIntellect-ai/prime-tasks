#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import re
import shlex
import shutil
import secrets
import subprocess
import tempfile
from collections import Counter
from decimal import Decimal
from pathlib import Path

import pytest


def test_datamash_installed():
    datamash_path = "/home/user/local/bin/datamash"
    assert os.path.isfile(datamash_path), f"{datamash_path} does not exist. Did you install datamash?"
    assert os.access(datamash_path, os.X_OK), f"{datamash_path} is not executable."

    binary = Path(datamash_path).read_bytes()
    assert binary[:4] == b"\x7fELF", "datamash must be a compiled ELF executable."
    assert len(binary) >= 20 and binary[4] == 2, "datamash must be a 64-bit executable."
    assert int.from_bytes(binary[18:20], "little") == 62, "datamash must be built for x86_64."

    version = subprocess.run(
        [datamash_path, "--version"], text=True, capture_output=True, timeout=10
    )
    assert version.returncode == 0, version.stderr
    assert re.search(r"^datamash \(GNU datamash\) 1\.8(?:\s|$)", version.stdout), (
        f"Expected GNU datamash 1.8, got: {version.stdout!r}"
    )

    sample = "B\t1.25\nA\t2\nB\t-0.25\nA\t4\n"
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    run = subprocess.run(
        [datamash_path, "-s", "-g", "1", "sum", "2", "mean", "2"],
        input=sample,
        text=True,
        capture_output=True,
        env=env,
        timeout=10,
    )
    assert run.returncode == 0, run.stderr
    rows = [line.split("\t") for line in run.stdout.splitlines() if line]
    assert len(rows) == 2 and all(len(row) == 3 for row in rows), run.stdout
    actual = {row[0]: (Decimal(row[1]), Decimal(row[2])) for row in rows}
    assert actual == {
        "A": (Decimal("6"), Decimal("3")),
        "B": (Decimal("1"), Decimal("0.5")),
    }


def test_process_data_script_exists():
    script_path = "/home/user/process_data.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK) or True, "Script should ideally be executable."


def test_cleaned_data_tsv():
    cleaned_path = "/home/user/cleaned_data.tsv"
    assert os.path.isfile(cleaned_path), f"Cleaned data file {cleaned_path} does not exist."

    with open(cleaned_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 8, f"Expected 8 valid rows in cleaned_data.tsv, found {len(lines)}."

    expected_rows = {
        "Exp1\t2022-12-31\tAlpha\t12.50",
        "Exp2\t2023-01-01\tBeta\t10.00",
        "Exp3\t2023-01-02\tAlpha\t5.25",
        "Exp5\t2023-01-04\tBeta\t20.00",
        "Exp6\t2023-10-15\tAlpha\t3.25",
        "Exp7\t2023-10-16\tBeta\t15.50",
        "Exp8\t2023-10-17\tGamma\t100.00",
        "Exp10\t2023-10-19\tGamma\t200.50"
    }

    actual_rows = set()
    for line in lines:
        parts = line.split("\t")
        assert len(parts) == 4, f"Row does not have 4 tab-separated columns: {line}"
        try:
            val = float(parts[3])
            parts[3] = f"{val:.2f}"
        except ValueError:
            pytest.fail(f"Value column contains non-float: {parts[3]} in row {line}")
        actual_rows.add("\t".join(parts))

    for expected in expected_rows:
        assert expected in actual_rows, f"Expected row '{expected}' not found in cleaned_data.tsv."


def test_summary_csv():
    summary_path = "/home/user/results/summary.csv"
    assert os.path.isfile(summary_path), f"Summary CSV {summary_path} does not exist."

    with open(summary_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Summary CSV is empty."

    header = rows[0]
    assert header == ["Category", "Total", "Average"], f"Incorrect header in summary.csv: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected 3 data rows in summary.csv, found {len(data_rows)}."
    assert [row[0] for row in data_rows] == sorted(row[0] for row in data_rows), (
        "Summary categories are not sorted alphabetically."
    )

    expected_data = {
        "Alpha": {"Total": 21.0, "Average": 7.0},
        "Beta": {"Total": 45.5, "Average": 15.166666666667},
        "Gamma": {"Total": 300.5, "Average": 150.25}
    }

    categories_found = set()
    for row in data_rows:
        assert len(row) == 3, f"Row does not have 3 columns: {row}"
        category, total_str, avg_str = row
        categories_found.add(category)
        assert category in expected_data, f"Unexpected category '{category}' found."

        try:
            total = float(total_str)
            avg = float(avg_str)
        except ValueError:
            pytest.fail(f"Non-numeric value in total/average for category {category}: {total_str}, {avg_str}")

        expected_total = expected_data[category]["Total"]
        expected_avg = expected_data[category]["Average"]
        assert math.isclose(total, expected_total, rel_tol=1e-5), f"Incorrect total for {category}: expected {expected_total}, got {total}"
        assert math.isclose(avg, expected_avg, rel_tol=1e-2), f"Incorrect average for {category}: expected {expected_avg}, got {avg}"

    assert categories_found == {"Alpha", "Beta", "Gamma"}, "Not all expected categories were found in summary.csv."


def test_script_on_altered_inputs_and_datamash_use():
    raw = Path("/home/user/raw_data")
    script = Path("/home/user/process_data.sh")
    datamash = Path("/home/user/local/bin/datamash")
    real_datamash = Path("/home/user/local/bin/datamash.verifier-real")
    cleaned = Path("/home/user/cleaned_data.tsv")
    summary = Path("/home/user/results/summary.csv")

    token = secrets.token_hex(5)
    categories = [f"Orchid{token}", f"Maple{token}", f"Cedar{token}"]
    c1, c2, c3 = categories
    ids = [f"R{token}{i}" for i in range(1, 8)]

    valid = [
        (ids[0], "2024-02-03", c1, "12.75"),
        (ids[1], "11/09/2021", c2, "-2,50"),
        (ids[2], "2020-12-31", c1, "7"),
        (ids[3], "03/04/2019", c3, "100,25"),
        (ids[4], "2018-07-06", c2, "9.125"),
        (ids[5], "08/15/2017", c3, "-20.00"),
        (ids[6], "2016-01-02", c1, "3,5"),
    ]
    expected_cleaned = Counter()
    values = {category: [] for category in categories}
    for experiment, date, category, value in valid:
        if "/" in date:
            month, day, year = date.split("/")
            date = f"{year}-{int(month):02d}-{int(day):02d}"
        normalized = value.replace(",", ".")
        expected_cleaned[(experiment, date, category, Decimal(normalized))] += 1
        values[category].append(Decimal(normalized))

    first_file = [
        "|".join(valid[0]),
        "|".join(valid[1]),
        "|".join(valid[2]),
        f"Bad{token}A|2022-01-01|{c1}|N/A",
        f"Bad{token}B|2022-01-01||5.0",
        f"Bad{token}C|2022-01-01|{c2}",
    ]
    second_file = [
        "|".join(valid[3]),
        "|".join(valid[4]),
        "|".join(valid[5]),
        "|".join(valid[6]),
        f"Bad{token}D|2022-01-01|{c3}|4|extra",
        f"Bad{token}E||{c1}|8.0",
        f"Bad{token}F|2022-01-01|{c2}|error",
    ]

    temp_root = Path(tempfile.mkdtemp(prefix="verifier-data-"))
    backup_raw = temp_root / "raw_data"
    marker = temp_root / "datamash.calls"
    shutil.copytree(raw, backup_raw)

    run = None
    calls = ""
    cleaned_text = None
    summary_text = None
    try:
        shutil.rmtree(raw)
        raw.mkdir(parents=True)
        (raw / f"part-{token}-a.txt").write_text("\n".join(first_file) + "\n", encoding="utf-8")
        (raw / f"part-{token}-b.txt").write_text("\n".join(second_file) + "\n", encoding="utf-8")

        if real_datamash.exists():
            real_datamash.unlink()
        os.replace(datamash, real_datamash)
        wrapper = (
            "#!/bin/bash\n"
            f"printf '%s\\n' \"$*\" >> {shlex.quote(str(marker))}\n"
            f"exec {shlex.quote(str(real_datamash))} \"$@\"\n"
        )
        datamash.write_text(wrapper, encoding="utf-8")
        datamash.chmod(0o755)

        run = subprocess.run(
            ["bash", str(script)],
            cwd="/home/user",
            text=True,
            capture_output=True,
            timeout=30,
            env={**os.environ, "LC_ALL": "C"},
        )
        calls = marker.read_text(encoding="utf-8") if marker.exists() else ""
        cleaned_text = cleaned.read_text(encoding="utf-8") if cleaned.exists() else None
        summary_text = summary.read_text(encoding="utf-8") if summary.exists() else None
    finally:
        if real_datamash.exists():
            if datamash.exists() or datamash.is_symlink():
                datamash.unlink()
            os.replace(real_datamash, datamash)
        if raw.exists():
            shutil.rmtree(raw)
        shutil.copytree(backup_raw, raw)
        shutil.rmtree(temp_root, ignore_errors=True)

    assert run is not None and run.returncode == 0, (
        f"process_data.sh failed on altered inputs:\nstdout={run.stdout if run else ''}\n"
        f"stderr={run.stderr if run else ''}"
    )
    assert calls.strip(), "process_data.sh did not invoke /home/user/local/bin/datamash."
    call_words = calls.replace("=", " ").split()
    assert "sum" in call_words and "mean" in call_words, (
        f"datamash was not used for both sum and mean aggregation; calls were: {calls!r}"
    )

    assert cleaned_text is not None, "The script did not create cleaned_data.tsv on altered inputs."
    actual_cleaned = Counter()
    for line in cleaned_text.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        assert len(parts) == 4, f"Altered-input cleaned row has wrong schema: {line!r}"
        try:
            value = Decimal(parts[3])
        except Exception:
            pytest.fail(f"Altered-input cleaned value is non-numeric: {parts[3]!r}")
        actual_cleaned[(parts[0], parts[1], parts[2], value)] += 1
    assert actual_cleaned == expected_cleaned, (
        f"cleaned_data.tsv was incorrect on altered inputs.\n"
        f"Expected: {expected_cleaned}\nActual: {actual_cleaned}"
    )

    assert summary_text is not None, "The script did not create summary.csv on altered inputs."
    rows = list(csv.reader(summary_text.splitlines()))
    assert rows and rows[0] == ["Category", "Total", "Average"], "Incorrect summary header."
    data_rows = rows[1:]
    expected_order = sorted(categories)
    assert [row[0] for row in data_rows] == expected_order, (
        "Summary categories must be sorted alphabetically."
    )
    assert len(data_rows) == len(categories)
    for row in data_rows:
        assert len(row) == 3
        category = row[0]
        assert category in values
        try:
            total = Decimal(row[1])
            average = Decimal(row[2])
        except Exception:
            pytest.fail(f"Non-numeric aggregate row: {row!r}")
        expected_total = sum(values[category], Decimal("0"))
        expected_average = expected_total / Decimal(len(values[category]))
        assert abs(total - expected_total) <= Decimal("0.011"), (
            f"Incorrect total for {category}: {total} instead of {expected_total}"
        )
        assert abs(average - expected_average) <= Decimal("0.011"), (
            f"Incorrect average for {category}: {average} instead of {expected_average}"
        )
TEST_EOF

if bash /home/user/process_data.sh && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
