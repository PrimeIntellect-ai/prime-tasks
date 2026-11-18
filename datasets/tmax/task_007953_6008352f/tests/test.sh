#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import stat
import secrets
import subprocess
from datetime import datetime, timezone

SOURCE_PATH = "/home/user/process_loc.c"
EXECUTABLE_PATH = "/tmp/process_loc_verified"
RAW_PATH = "/home/user/loc_data/raw_translations.txt"
CSV_PATH = "/home/user/loc_data/processed.csv"
LOG_PATH = "/home/user/loc_data/pipeline.log"


def parse_timestamp(ts_str):
    try:
        return int(ts_str)
    except ValueError:
        dt = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
        dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())


def compute_expected_data(raw_file_path):
    if not os.path.exists(raw_file_path):
        return None

    records = []
    with open(raw_file_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) != 4:
                continue
            string_id, ts_str, conf_str, locale = parts
            ts = parse_timestamp(ts_str)
            conf = float(conf_str)
            records.append({
                "string_id": string_id,
                "ts": ts,
                "conf": conf,
                "locale": locale
            })

    total_raw = len(records)

    # Deduplicate by (StringID, Locale), retaining the first record on ties.
    groups = {}
    for rec in records:
        key = (rec["string_id"], rec["locale"])
        if key not in groups:
            groups[key] = rec
        elif rec["ts"] > groups[key]["ts"]:
            groups[key] = rec

    deduped = list(groups.values())
    total_dedup = len(deduped)

    if total_dedup > 0:
        min_conf = min(r["conf"] for r in deduped)
        max_conf = max(r["conf"] for r in deduped)
    else:
        min_conf = 0.0
        max_conf = 0.0

    for rec in deduped:
        if max_conf > min_conf:
            rec["norm_conf"] = (rec["conf"] - min_conf) / (max_conf - min_conf)
        else:
            rec["norm_conf"] = 0.0

    deduped.sort(key=lambda x: (x["string_id"], x["locale"]))
    return {
        "total_raw": total_raw,
        "total_dedup": total_dedup,
        "min_conf": min_conf,
        "max_conf": max_conf,
        "records": deduped
    }


def test_00_program_exists_and_compiles():
    try:
        mode = os.lstat(SOURCE_PATH).st_mode
    except FileNotFoundError:
        assert False, f"Required C source {SOURCE_PATH} does not exist."
    assert stat.S_ISREG(mode), f"{SOURCE_PATH} must be a regular C source file."

    result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30
    )
    assert result.returncode == 0, f"C program failed to compile with gcc:\n{result.stderr}"
    assert os.path.isfile(EXECUTABLE_PATH), "gcc did not produce an executable."


def test_10_processed_csv_exists_and_correct():
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist."

    expected = compute_expected_data(RAW_PATH)
    assert expected is not None, f"Input file {RAW_PATH} is missing."

    with open(CSV_PATH, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."
    header = rows[0]
    expected_header = ["StringID", "Locale", "UnixTimestamp", "NormalizedConfidence"]
    assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == len(expected["records"]), f"Expected {len(expected['records'])} data rows, got {len(data_rows)}."

    for i, (actual_row, exp_rec) in enumerate(zip(data_rows, expected["records"])):
        assert len(actual_row) == 4, f"Row {i+1} does not have 4 columns."
        assert actual_row[0] == exp_rec["string_id"], f"Row {i+1} StringID mismatch."
        assert actual_row[1] == exp_rec["locale"], f"Row {i+1} Locale mismatch."
        assert int(actual_row[2]) == exp_rec["ts"], f"Row {i+1} UnixTimestamp mismatch."
        assert f"{float(actual_row[3]):.4f}" == f"{exp_rec['norm_conf']:.4f}", f"Row {i+1} NormalizedConfidence mismatch."


def test_20_pipeline_log_exists_and_correct():
    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} does not exist."

    expected = compute_expected_data(RAW_PATH)
    assert expected is not None, f"Input file {RAW_PATH} is missing."

    with open(LOG_PATH, "r") as f:
        log_content = f.read().strip().split("\n")

    log_dict = {}
    for line in log_content:
        if ":" in line:
            k, v = line.split(":", 1)
            log_dict[k.strip()] = v.strip()

    assert "TOTAL_RAW" in log_dict, "TOTAL_RAW missing from log."
    assert int(log_dict["TOTAL_RAW"]) == expected["total_raw"], "TOTAL_RAW value is incorrect."

    assert "TOTAL_DEDUPLICATED" in log_dict, "TOTAL_DEDUPLICATED missing from log."
    assert int(log_dict["TOTAL_DEDUPLICATED"]) == expected["total_dedup"], "TOTAL_DEDUPLICATED value is incorrect."

    assert "MIN_CONF" in log_dict, "MIN_CONF missing from log."
    assert f"{float(log_dict['MIN_CONF']):.2f}" == f"{expected['min_conf']:.2f}", "MIN_CONF value is incorrect."

    assert "MAX_CONF" in log_dict, "MAX_CONF missing from log."
    assert f"{float(log_dict['MAX_CONF']):.2f}" == f"{expected['max_conf']:.2f}", "MAX_CONF value is incorrect."


def iso_timestamp(epoch):
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_if_present(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return f.read()


def restore_file(path, content):
    if content is None:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    else:
        with open(path, "wb") as f:
            f.write(content)


def assert_generated_outputs(expected):
    assert os.path.exists(CSV_PATH), "Executed program did not generate processed.csv."
    assert os.path.exists(LOG_PATH), "Executed program did not generate pipeline.log."

    with open(CSV_PATH, "r", newline="") as f:
        actual_rows = list(csv.reader(f))

    expected_rows = [["StringID", "Locale", "UnixTimestamp", "NormalizedConfidence"]]
    for rec in expected["records"]:
        expected_rows.append([
            rec["string_id"],
            rec["locale"],
            str(rec["ts"]),
            f"{rec['norm_conf']:.4f}"
        ])
    assert actual_rows == expected_rows, f"Executed program produced incorrect CSV. Expected {expected_rows}, got {actual_rows}."

    expected_log = [
        f"TOTAL_RAW: {expected['total_raw']}",
        f"TOTAL_DEDUPLICATED: {expected['total_dedup']}",
        f"MIN_CONF: {expected['min_conf']:.2f}",
        f"MAX_CONF: {expected['max_conf']:.2f}"
    ]
    with open(LOG_PATH, "r") as f:
        actual_log = f.read().strip().splitlines()
    assert actual_log == expected_log, f"Executed program produced incorrect log. Expected {expected_log}, got {actual_log}."


def test_90_execute_program_on_unseen_inputs():
    saved_raw = read_if_present(RAW_PATH)
    saved_csv = read_if_present(CSV_PATH)
    saved_log = read_if_present(LOG_PATH)

    try:
        for _ in range(2):
            tag = secrets.token_hex(4).upper()
            base_epoch = 1600000000 + secrets.randbelow(90000000)
            score_base = 10 + secrets.randbelow(80)

            alpha = f"ALPHA_{tag}"
            beta = f"BETA_{tag}"
            menu = f"MENU_{tag}"
            zeta = f"ZETA_{tag}"

            lines = [
                f"{zeta}|{base_epoch}|{score_base + 5}.0|en-US",
                f"{zeta}|{iso_timestamp(base_epoch + 7200)}|{score_base + 35}.0|en-US",
                f"{alpha}|{base_epoch + 100}|{score_base + 10}.0|fr-FR",
                f"{alpha}|{iso_timestamp(base_epoch + 100)}|{score_base + 90}.0|fr-FR",
                f"{alpha}|{base_epoch + 500}|{score_base + 20}.0|en-US",
                f"{menu}|{iso_timestamp(base_epoch + 86400)}|{score_base + 70}.0|de-DE",
                f"{menu}|{base_epoch + 800}|{score_base + 80}.0|de-DE",
                f"{beta}|{base_epoch + 900}|{score_base}.0|ja-JP"
            ]

            with open(RAW_PATH, "w") as f:
                f.write("\n".join(lines) + "\n")
            expected = compute_expected_data(RAW_PATH)

            for path in (CSV_PATH, LOG_PATH):
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass

            env = os.environ.copy()
            env["TZ"] = "UTC"
            result = subprocess.run(
                [EXECUTABLE_PATH],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                timeout=15
            )
            assert result.returncode == 0, f"Compiled program failed when executed:\n{result.stderr}"
            assert_generated_outputs(expected)
    finally:
        restore_file(RAW_PATH, saved_raw)
        restore_file(CSV_PATH, saved_csv)
        restore_file(LOG_PATH, saved_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
