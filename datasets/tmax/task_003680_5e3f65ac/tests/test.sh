#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess
from io import StringIO

FALLBACKS_CSV = "/home/user/fallbacks.csv"
SANITIZER_SRC = "/home/user/loc_sanitizer.c"
SANITIZER_BIN = "/home/user/loc_sanitizer"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"


def test_fallbacks_extracted():
    assert os.path.isfile(FALLBACKS_CSV), f"Missing {FALLBACKS_CSV}"
    with open(FALLBACKS_CSV, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_pairs = {
        ("es-AR", "es-ES"),
        ("fr-CA", "fr-FR"),
        ("pt-BR", "pt-PT"),
        ("zh-HK", "zh-TW"),
    }
    actual_pairs = set()
    for line in content.splitlines():
        parts = line.split(",")
        if len(parts) == 2:
            actual_pairs.add((parts[0].strip(), parts[1].strip()))

    missing = expected_pairs - actual_pairs
    assert not missing, f"Missing fallback pairs in {FALLBACKS_CSV}: {missing}"


def test_sanitizer_executable():
    assert os.path.isfile(SANITIZER_SRC), f"Missing {SANITIZER_SRC}"
    assert os.path.isfile(SANITIZER_BIN), f"Missing {SANITIZER_BIN}"
    assert os.access(SANITIZER_BIN, os.X_OK), f"{SANITIZER_BIN} is not executable"
    with open(SANITIZER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "loc_sanitizer is not a compiled executable"


def compute_expected_clean(input_text, fallbacks):
    reader = csv.reader(StringIO(input_text))
    output = StringIO()
    writer = csv.writer(output, lineterminator="\n")
    for row in reader:
        if len(row) >= 3:
            loc, trans = row[1], row[2]
            if not trans and loc in fallbacks:
                row[2] = "[FALLBACK_APPLIED]"
        writer.writerow(row)
    return output.getvalue()


def test_corpus_processing():
    assert os.path.isfile(SANITIZER_BIN), "Sanitizer binary not found."

    fallbacks = {}
    if os.path.isfile(FALLBACKS_CSV):
        with open(FALLBACKS_CSV, "r", encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split(",")
                if len(parts) == 2:
                    fallbacks[parts[0]] = parts[1]

    clean_failed = []
    if os.path.isdir(CLEAN_CORPUS):
        for fname in os.listdir(CLEAN_CORPUS):
            if not fname.endswith(".csv"):
                continue
            fpath = os.path.join(CLEAN_CORPUS, fname)
            with open(fpath, "rb") as f:
                input_bytes = f.read()
            proc = subprocess.run(
                [SANITIZER_BIN, FALLBACKS_CSV],
                input=input_bytes,
                capture_output=True,
                timeout=10,
            )
            actual = proc.stdout.decode("utf-8", errors="replace").replace("\r\n", "\n")
            expected = compute_expected_clean(
                input_bytes.decode("utf-8"), fallbacks
            ).replace("\r\n", "\n")
            if actual.strip() != expected.strip():
                clean_failed.append(fname)

    evil_failed = []
    if os.path.isdir(EVIL_CORPUS):
        for fname in os.listdir(EVIL_CORPUS):
            if not fname.endswith(".csv"):
                continue
            fpath = os.path.join(EVIL_CORPUS, fname)
            with open(fpath, "rb") as f:
                input_bytes = f.read()
            proc = subprocess.run(
                [SANITIZER_BIN, FALLBACKS_CSV],
                input=input_bytes,
                capture_output=True,
                timeout=10,
            )
            try:
                proc.stdout.decode("utf-8", errors="strict")
            except UnicodeDecodeError:
                evil_failed.append(fname)

    errors = []
    if clean_failed:
        errors.append(
            f"{len(clean_failed)} clean files modified or incorrectly processed: "
            + ", ".join(clean_failed)
        )
    if evil_failed:
        errors.append(
            f"{len(evil_failed)} evil files bypassed validation (emitted invalid UTF-8): "
            + ", ".join(evil_failed)
        )
    assert not errors, " | ".join(errors)


def encode_rows(rows):
    out = StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerows(rows)
    return out.getvalue().encode("utf-8")


def run_and_parse(input_bytes, fallback_path):
    proc = subprocess.run(
        [SANITIZER_BIN, fallback_path],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, proc.stderr.decode("utf-8", errors="replace")
    text = proc.stdout.decode("utf-8", errors="strict")
    return list(csv.reader(StringIO(text), strict=True))


def test_dynamic_csv_parsing_and_gap_filling(tmp_path):
    token = secrets.token_hex(8)
    mapped_locale = f"x-test-{token}"
    target_locale = f"x-target-{token}"
    unmapped_locale = f"x-none-{token}"
    fallback_path = tmp_path / "fallbacks.csv"
    fallback_path.write_text(
        f"{mapped_locale},{target_locale}\n", encoding="utf-8"
    )

    rows = [
        ["MessageID", "Locale", "Translation"],
        [f"plain-{token}", "en-US", "café 日本語 🙂"],
        [f"multi-{token}", "en-US", "first line, with comma\nsecond line"],
        [f"quote-{token}", "en-US", "He said \"hello\", then left"],
        [f"filled-{token}", mapped_locale, ""],
        [f"unmapped-{token}", unmapped_locale, ""],
    ]
    expected = [row[:] for row in rows]
    expected[4][2] = "[FALLBACK_APPLIED]"

    actual = run_and_parse(encode_rows(rows), str(fallback_path))
    assert actual == expected


def test_invalid_utf8_rows_are_dropped_without_losing_neighbors(tmp_path):
    token = secrets.token_hex(8)
    fallback_path = tmp_path / "fallbacks.csv"
    fallback_path.write_text("aa-AA,bb-BB\n", encoding="utf-8")

    header = [["MessageID", "Locale", "Translation"]]
    good_before = [[f"good-before-{token}", "en-US", "valid café"]]
    good_after = [[f"good-after-{token}", "en-US", "valid after\nnewline, comma"]]

    payload = bytearray()
    payload.extend(encode_rows(header + good_before))
    payload.extend(b"bad-id-\xff,en-US,text\n")
    payload.extend(b"bad-locale,en-\xc3(,text\n")
    payload.extend(b"bad-translation,en-US,overlong-\xe0\x80\x80\n")
    payload.extend(b'bad-quoted,en-US,"first line\ninvalid-\xed\xa0\x80,still field"\n')
    payload.extend(encode_rows(good_after))

    actual = run_and_parse(bytes(payload), str(fallback_path))
    assert actual == header + good_before + good_after
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
