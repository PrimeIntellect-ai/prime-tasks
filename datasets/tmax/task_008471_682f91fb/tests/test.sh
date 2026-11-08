#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import csv
import json
import os
import re
import secrets
import stat
import subprocess
import xml.etree.ElementTree as ET

import pandas as pd
import pytest

PROCESS = "/home/user/process_locs.py"
RUNNER = "/home/user/run_pipeline.sh"
DROPS = "/home/user/loc_drops"
PROCESSED = "/home/user/processed"

# Add unpredictable records before executing the submitted pipeline. Records in
# one bucket are split across files to ensure all input files are aggregated.
TOKEN = secrets.token_hex(6)
DYNAMIC_DATE = "2097-07-19"
DYNAMIC_LANG = f"qa-{TOKEN}"
SECOND_DATE = "2097-07-20"
SECOND_LANG = f"qb-{TOKEN}"
MARKER1 = f"BROKEN_{TOKEN}_ONE"
MARKER2 = f"BROKEN_{TOKEN}_TWO"


def malformed_line(record, marker, bad_escape):
    encoded = json.dumps(record, ensure_ascii=False)
    assert marker in encoded
    return encoded.replace(marker, "\\" + "u" + bad_escape)


records_a = [
    {
        "timestamp": f"{DYNAMIC_DATE}T01:02:03Z",
        "lang": DYNAMIC_LANG,
        "key": f"special_{TOKEN}",
        "value": '<tag> & "quoted", comma\nnext',
    },
    {
        "timestamp": f"{DYNAMIC_DATE}T02:03:04Z",
        "lang": DYNAMIC_LANG,
        "key": f"broken_a_{TOKEN}",
        "value": f"before {MARKER1} after",
    },
]
records_b = [
    {
        "timestamp": f"{DYNAMIC_DATE}T03:04:05Z",
        "lang": DYNAMIC_LANG,
        "key": f"unicode_{TOKEN}",
        "value": "Καλημέρα 世界",
    },
    {
        "timestamp": f"{SECOND_DATE}T04:05:06Z",
        "lang": SECOND_LANG,
        "key": f"broken_b_{TOKEN}",
        "value": f"left {MARKER2} right",
    },
]

with open(os.path.join(DROPS, f"audit_a_{TOKEN}.jsonl"), "w", encoding="utf-8") as f:
    f.write(json.dumps(records_a[0], ensure_ascii=False) + "\n")
    f.write(malformed_line(records_a[1], MARKER1, "12G4") + "\n")
with open(os.path.join(DROPS, f"audit_b_{TOKEN}.jsonl"), "w", encoding="utf-8") as f:
    f.write(json.dumps(records_b[0], ensure_ascii=False) + "\n")
    f.write(malformed_line(records_b[1], MARKER2, "XYZ1") + "\n")


INVALID_ESCAPE = re.compile(r"\\u(.{4})")
HEX = set("0123456789abcdefABCDEF")


def clean_line(line):
    def replace(match):
        chars = match.group(1)
        return match.group(0) if all(c in HEX for c in chars) else "[ERR]"
    return INVALID_ESCAPE.sub(replace, line)


def expected_groups():
    groups = collections.defaultdict(list)
    for filename in sorted(os.listdir(DROPS)):
        if not filename.endswith(".jsonl"):
            continue
        with open(os.path.join(DROPS, filename), encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                record = json.loads(clean_line(line))
                groups[(record["timestamp"][:10], record["lang"])].append(
                    (record["key"], record["value"])
                )
    return groups


def assert_parallel_api_used():
    with open(PROCESS, encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=PROCESS)

    imported = False
    constructor_aliases = set()
    parallel_names = {
        "Pool", "Process", "ProcessPoolExecutor", "ThreadPoolExecutor"
    }
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "multiprocessing" or alias.name.startswith("concurrent.futures"):
                    imported = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == "multiprocessing" or node.module.startswith("concurrent.futures")):
                imported = True
                for alias in node.names:
                    if alias.name in parallel_names:
                        constructor_aliases.add(alias.asname or alias.name)

    used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in constructor_aliases:
            used = True
        elif isinstance(node.func, ast.Attribute) and node.func.attr in parallel_names:
            used = True

    assert imported, "process_locs.py must import multiprocessing or concurrent.futures"
    assert used, "process_locs.py must construct a multiprocessing or futures worker API"


def run_as_user(command, timeout=120):
    result = subprocess.run(
        ["runuser", "-u", "user", "--"] + command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert result.returncode == 0, result.stdout


def test_pipeline_artifacts_execute_and_use_parallel_api():
    assert os.path.isfile(PROCESS), f"Missing Python pipeline: {PROCESS}"
    assert os.path.isfile(RUNNER), f"Missing runner: {RUNNER}"
    assert os.stat(RUNNER).st_mode & stat.S_IXUSR, "run_pipeline.sh is not executable"
    with open(RUNNER, encoding="utf-8") as f:
        runner_source = f.read()
    assert "process_locs.py" in runner_source, "run_pipeline.sh does not execute process_locs.py"

    assert_parallel_api_used()
    run_as_user([RUNNER])
    # Also execute the demanded Python artifact directly rather than trusting
    # pre-created output or a runner that performs unrelated work.
    run_as_user(["python3", PROCESS])


def test_crontab_configured():
    try:
        cron_out = subprocess.check_output(["crontab", "-u", "user", "-l"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read user user's crontab. Ensure a crontab is installed for that user.")

    assert "0 2 * * *" in cron_out, "Crontab does not have the correct schedule (0 2 * * *)."
    assert "run_pipeline.sh" in cron_out, "Crontab does not execute run_pipeline.sh."


def test_processed_files_exist():
    expected_files = [
        "/home/user/processed/2023-11-01/lang_fr-FR.csv",
        "/home/user/processed/2023-11-01/lang_fr-FR.xml",
        "/home/user/processed/2023-11-01/lang_fr-FR.parquet",
        "/home/user/processed/2023-11-01/lang_es-ES.csv",
        "/home/user/processed/2023-11-01/lang_es-ES.xml",
        "/home/user/processed/2023-11-01/lang_es-ES.parquet",
        "/home/user/processed/2023-11-02/lang_fr-FR.csv",
        "/home/user/processed/2023-11-02/lang_fr-FR.xml",
        "/home/user/processed/2023-11-02/lang_fr-FR.parquet",
        "/home/user/processed/2023-11-02/lang_es-ES.csv",
        "/home/user/processed/2023-11-02/lang_es-ES.xml",
        "/home/user/processed/2023-11-02/lang_es-ES.parquet",
    ]
    for file_path in expected_files:
        assert os.path.exists(file_path), f"Expected output file missing: {file_path}"


def test_every_group_and_format_has_exact_contents():
    for (date, lang), expected in expected_groups().items():
        base = os.path.join(PROCESSED, date, f"lang_{lang}")
        csv_path = base + ".csv"
        parquet_path = base + ".parquet"
        xml_path = base + ".xml"
        for path in (csv_path, parquet_path, xml_path):
            assert os.path.isfile(path), f"Expected output file missing: {path}"

        with open(csv_path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == ["key", "value"]
            csv_rows = [(row["key"], row["value"]) for row in reader]
        assert collections.Counter(csv_rows) == collections.Counter(expected)

        with open(parquet_path, "rb") as f:
            assert f.read(4) == b"PAR1", f"File {parquet_path} is missing Parquet magic bytes"
        frame = pd.read_parquet(parquet_path)
        assert list(frame.columns) == ["key", "value"]
        parquet_rows = [(str(k), str(v)) for k, v in frame[["key", "value"]].itertuples(index=False, name=None)]
        assert collections.Counter(parquet_rows) == collections.Counter(expected)

        try:
            root = ET.parse(xml_path).getroot()
        except ET.ParseError as exc:
            pytest.fail(f"Failed to parse XML file {xml_path}: {exc}")
        assert root.tag == "resources"
        xml_rows = []
        for child in root:
            assert child.tag == "string"
            assert set(child.attrib) == {"name"}
            xml_rows.append((child.attrib["name"], child.text or ""))
        assert collections.Counter(xml_rows) == collections.Counter(expected)


def test_data_cleaning_csv():
    fr_csv = "/home/user/processed/2023-11-01/lang_fr-FR.csv"
    assert os.path.exists(fr_csv), f"Missing {fr_csv}"
    with open(fr_csv, "r", encoding="utf-8") as f:
        content = f.read()
        assert "[ERR]" in content, f"Expected invalid unicode to be replaced with [ERR] in {fr_csv}"
        assert "ZZZZ" not in content, f"Invalid unicode sequence ZZZZ was not removed in {fr_csv}"

    es_csv = "/home/user/processed/2023-11-02/lang_es-ES.csv"
    assert os.path.exists(es_csv), f"Missing {es_csv}"
    with open(es_csv, "r", encoding="utf-8") as f:
        content = f.read()
        assert "[ERR]" in content, f"Expected invalid unicode to be replaced with [ERR] in {es_csv}"
        assert "12XY" not in content, f"Invalid unicode sequence 12XY was not removed in {es_csv}"


def test_xml_structure():
    es_xml = "/home/user/processed/2023-11-01/lang_es-ES.xml"
    assert os.path.exists(es_xml), f"Missing {es_xml}"
    try:
        root = ET.parse(es_xml).getroot()
    except ET.ParseError:
        pytest.fail(f"Failed to parse XML file: {es_xml}")
    assert root.tag == "resources", "XML root element must be <resources>"
    assert len(root) > 0, "XML <resources> element is empty"
    welcome_element = None
    for child in root:
        if child.tag == "string" and child.attrib.get("name") == "welcome":
            welcome_element = child
            break
    assert welcome_element is not None, 'Could not find <string name="welcome"> in XML'
    assert welcome_element.text == "Hola !", f"Expected 'Hola !', got '{welcome_element.text}'"


def test_parquet_format():
    fr_parquet = "/home/user/processed/2023-11-01/lang_fr-FR.parquet"
    assert os.path.exists(fr_parquet), f"Missing {fr_parquet}"
    with open(fr_parquet, "rb") as f:
        magic = f.read(4)
        assert magic == b"PAR1", f"File {fr_parquet} does not appear to be a valid Parquet file (missing PAR1 magic bytes)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
