#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess
import tempfile
import unicodedata

SCRIPT_PATH = "/home/user/etl_filter.py"
CLEAN_DIR = "/app/data/clean"
EVIL_DIR = "/app/data/evil"
LEGACY_CALC = "/app/bin/legacy_calc"

SUPERSCRIPT_DIGITS = str.maketrans({
    "⁰": "^0", "¹": "^1", "²": "^2", "³": "^3", "⁴": "^4",
    "⁵": "^5", "⁶": "^6", "⁷": "^7", "⁸": "^8", "⁹": "^9",
})
VALID_ASCII = re.compile(r"^[A-Za-z0-9 .+*/^=()\-]*$")


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."


def normalize_truth(line: str) -> str:
    # Preserve superscript meaning before NFKC would flatten the digits.
    norm = line.translate(SUPERSCRIPT_DIGITS)
    norm = unicodedata.normalize("NFKC", norm)
    norm = "".join(ch for ch in norm if unicodedata.category(ch) != "Cf")
    return norm


def is_safe_truth(norm: str) -> bool:
    if VALID_ASCII.fullmatch(norm) is None:
        return False
    depth = 0
    for ch in norm:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


def expected_output(line: str) -> str:
    norm = normalize_truth(line)
    return f"SAFE: {norm}" if is_safe_truth(norm) else "REJECT"


def run_script_on_file(filepath: str):
    result = subprocess.run(
        ["python3", SCRIPT_PATH, filepath],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Filter exited with {result.returncode} for {filepath}: {result.stderr}"
    )
    return result.stdout.splitlines()


def read_lines(filepath: str):
    with open(filepath, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def check_with_legacy(normalized: str):
    calc_proc = subprocess.run(
        [LEGACY_CALC],
        input=normalized + "\n",
        capture_output=True,
        text=True,
        timeout=5,
    )
    return calc_proc.returncode == 0


def test_evil_corpus():
    evil_files = [
        os.path.join(EVIL_DIR, f)
        for f in os.listdir(EVIL_DIR)
        if os.path.isfile(os.path.join(EVIL_DIR, f))
    ]
    bypassed = []

    for filepath in evil_files:
        outputs = run_script_on_file(filepath)
        lines = read_lines(filepath)

        if len(outputs) != len(lines):
            bypassed.append(
                f"{os.path.basename(filepath)} output count {len(outputs)} != input count {len(lines)}"
            )
            continue

        for i, output in enumerate(outputs):
            if output != "REJECT":
                bypassed.append(
                    f"{os.path.basename(filepath)}:{i+1} (Output: {output})"
                )

    assert not bypassed, (
        f"{len(bypassed)} evil lines bypassed REJECT: " + ", ".join(bypassed[:5])
    )


def test_clean_corpus():
    clean_files = [
        os.path.join(CLEAN_DIR, f)
        for f in os.listdir(CLEAN_DIR)
        if os.path.isfile(os.path.join(CLEAN_DIR, f))
    ]
    modified_or_rejected = []

    for filepath in clean_files:
        outputs = run_script_on_file(filepath)
        lines = read_lines(filepath)

        if len(outputs) != len(lines):
            modified_or_rejected.append(
                f"{os.path.basename(filepath)} output count {len(outputs)} != input count {len(lines)}"
            )
            continue

        for i, (line, output) in enumerate(zip(lines, outputs)):
            if not output.startswith("SAFE: "):
                modified_or_rejected.append(
                    f"{os.path.basename(filepath)}:{i+1} rejected or invalid format"
                )
                continue

            expected = expected_output(line)
            if not expected.startswith("SAFE: "):
                modified_or_rejected.append(
                    f"{os.path.basename(filepath)}:{i+1} is not a valid clean fixture"
                )
                continue

            if output != expected:
                modified_or_rejected.append(
                    f"{os.path.basename(filepath)}:{i+1} incorrect normalization: "
                    f"expected {expected!r}, got {output!r}"
                )
                continue

            normalized = output[6:]
            if not check_with_legacy(normalized):
                modified_or_rejected.append(
                    f"{os.path.basename(filepath)}:{i+1} produced unsafe string for legacy_calc: {normalized}"
                )

    assert not modified_or_rejected, (
        f"{len(modified_or_rejected)} clean lines failed: "
        + ", ".join(modified_or_rejected[:5])
    )


def to_fullwidth(text: str) -> str:
    return "".join(
        chr(ord(ch) + 0xFEE0) if 0x21 <= ord(ch) <= 0x7E else ch
        for ch in text
    )


def test_derived_unseen_inputs():
    rng = random.SystemRandom()
    superscripts = "⁰¹²³⁴⁵⁶⁷⁸⁹"
    invisible = ["\u200b", "\u200c", "\u200d", "\u2060", "\ufeff"]
    lines = []

    for _ in range(12):
        left = rng.randint(10, 999)
        right = rng.randint(1, 99)
        power = rng.randint(0, 9)
        raw = f"(x + {left}){superscripts[power]} = y / {right}"
        raw = to_fullwidth(raw)
        pos = rng.randrange(len(raw) + 1)
        raw = raw[:pos] + rng.choice(invisible) + raw[pos:]
        lines.append(raw)

    # Lexically illegal and structurally malformed cases.
    lines.extend([
        "x ＋ 1 # payload",
        "(a + b",
        "a + b))",
        ")x + 1(",
        "x = 42;",
        "x + [1]",
        "a;drop",
        "(x + 2)) + (3",
    ])

    expected = [expected_output(line) for line in lines]
    fd, path = tempfile.mkstemp(prefix="etl_unseen_", suffix=".txt", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            for line in lines:
                f.write(line + "\n")

        outputs = run_script_on_file(path)
        assert len(outputs) == len(lines), (
            f"Output count {len(outputs)} != input count {len(lines)} on derived inputs"
        )
        assert outputs == expected, "Filter outputs do not match derived normalization/validation results"

        for output in outputs:
            if output.startswith("SAFE: "):
                assert check_with_legacy(output[6:]), (
                    f"Derived SAFE output crashes legacy_calc: {output}"
                )
    finally:
        os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
