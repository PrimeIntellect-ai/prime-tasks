#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import secrets
import shlex
import stat
import subprocess

import pytest

EXPECTED_TIMESTAMPS = [
    1697121000,
    1697121060,
    1697121120,
    1697121180,
    1697121240,
]

DATASET = "/home/user/data/events.jsonl"
CLEANER_SOURCE = "/home/user/cleaner.c"
CLEANER = "/home/user/cleaner"
EXTRACTOR = "/app/legacy_extractor"
OUTPUT = "/home/user/output.csv"
SUMMARY = "/home/user/summary.txt"


def expected_rows(dataset_bytes, extractor_path):
    sanitized = dataset_bytes.replace(b"\\u", b"__")
    proc = subprocess.run(
        [extractor_path],
        input=sanitized,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=False,
    )
    assert proc.returncode == 0, f"Reference extractor failed: {proc.stderr!r}"

    rows = []
    for raw_line in proc.stdout.decode("utf-8").splitlines():
        timestamp, score = raw_line.strip().split(",")
        dt = datetime.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
        rows.append((int(dt.timestamp()), int(score)))
    return rows


def read_output():
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist."
    rows = []
    with open(OUTPUT, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            fields = line.strip().split(",")
            assert len(fields) == 2, f"Malformed output row: {line!r}"
            rows.append((int(fields[0]), int(fields[1])))
    return rows


@pytest.fixture(scope="session", autouse=True)
def pipeline_state():
    assert os.path.isfile(CLEANER_SOURCE), f"C source {CLEANER_SOURCE} does not exist."
    assert os.path.isfile(CLEANER), f"Executable {CLEANER} does not exist."
    mode = os.stat(CLEANER).st_mode
    assert stat.S_ISREG(mode) and os.access(CLEANER, os.X_OK), f"{CLEANER} is not an executable regular file."
    with open(CLEANER, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{CLEANER} is not a compiled ELF executable."

    original_dataset = open(DATASET, "rb").read()
    real_extractor = f"/app/legacy_extractor.verifier-{secrets.token_hex(8)}"
    marker = f"/tmp/legacy-called-{secrets.token_hex(16)}"
    extractor_moved = False

    def run_cleaner(executable=CLEANER):
        for path in (OUTPUT, SUMMARY, marker):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        proc = subprocess.run(
            [executable],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert proc.returncode == 0, (
            f"Cleaner exited with status {proc.returncode}: {proc.stderr.decode(errors='replace')}"
        )
        assert os.path.exists(marker), "The cleaner did not invoke /app/legacy_extractor."
        rows = read_output()
        assert os.path.exists(SUMMARY), f"Summary file {SUMMARY} does not exist."
        with open(SUMMARY, "r", encoding="utf-8") as f:
            summary = f.read().strip()
        return rows, summary

    try:
        original_expected = expected_rows(original_dataset, EXTRACTOR)

        os.rename(EXTRACTOR, real_extractor)
        extractor_moved = True
        wrapper = (
            "#!/bin/sh\n"
            f"printf 'called\\n' >> {shlex.quote(marker)}\n"
            f"exec {shlex.quote(real_extractor)} \"$@\"\n"
        )
        with open(EXTRACTOR, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(EXTRACTOR, 0o755)

        original_rows, original_summary = run_cleaner()
        yield {
            "original_dataset": original_dataset,
            "original_expected": original_expected,
            "original_rows": original_rows,
            "original_summary": original_summary,
            "real_extractor": real_extractor,
            "run_cleaner": run_cleaner,
        }
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        try:
            os.unlink(EXTRACTOR)
        except FileNotFoundError:
            pass
        if extractor_moved and os.path.exists(real_extractor):
            os.rename(real_extractor, EXTRACTOR)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass


def test_output_csv_row_accuracy(pipeline_state):
    rows = pipeline_state["original_rows"]
    expected = pipeline_state["original_expected"]

    correct_rows = 0
    for i, (timestamp, score) in enumerate(rows):
        if i >= len(EXPECTED_TIMESTAMPS):
            break
        if timestamp == EXPECTED_TIMESTAMPS[i]:
            correct_rows += 1

    row_accuracy = correct_rows / len(EXPECTED_TIMESTAMPS)
    assert row_accuracy >= 0.99, f"row_accuracy={row_accuracy} is below threshold 0.99"
    assert rows == expected, f"Output rows, including feature scores, are incorrect: {rows!r}"


def test_summary_txt_content(pipeline_state):
    expected_text = "Report: Processed 5 valid events."
    content = pipeline_state["original_summary"]
    assert content == expected_text, (
        f"Summary file content is incorrect. Expected {expected_text!r}, got {content!r}"
    )


def test_original_dataset_unmodified(pipeline_state):
    assert os.path.exists(DATASET), f"Original dataset {DATASET} is missing."
    with open(DATASET, "r", encoding="utf-8") as f:
        content = f.read()

    assert r"\u0041" in content, "Original dataset was modified (missing \\u0041)"
    assert r"\u26A0" in content, "Original dataset was modified (missing \\u26A0)"
    assert "System boot normal" in content, "Original dataset was modified (missing first line)"
    assert open(DATASET, "rb").read() == pipeline_state["original_dataset"], "Original dataset was modified."


def test_pipeline_on_derived_inputs(pipeline_state):
    token = secrets.token_hex(10)
    timestamps = [
        "2024-01-02T03:04:05Z",
        "2024-02-03T04:05:06Z",
        "2024-03-04T05:06:07Z",
        "2024-04-05T06:07:08Z",
        "2024-05-06T07:08:09Z",
    ]
    lines = []
    for i, timestamp in enumerate(timestamps):
        pad = token + ("x" * (i * 7 + 1))
        message = f"dynamic-{i}-{token}"
        if i in (1, 3):
            message += r"-unicode-\u2603"
        lines.append(
            f'{{"pad":"{pad}","timestamp":"{timestamp}","message":"{message}"}}'
        )
    dynamic_dataset = ("\n".join(lines) + "\n").encode("utf-8")
    expected = expected_rows(dynamic_dataset, pipeline_state["real_extractor"])

    try:
        with open(DATASET, "wb") as f:
            f.write(dynamic_dataset)
        rows, summary = pipeline_state["run_cleaner"]()
        assert rows == expected, f"Cleaner failed on derived inputs: expected {expected!r}, got {rows!r}"
        assert summary == "Report: Processed 5 valid events."
    finally:
        with open(DATASET, "wb") as f:
            f.write(pipeline_state["original_dataset"])

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
