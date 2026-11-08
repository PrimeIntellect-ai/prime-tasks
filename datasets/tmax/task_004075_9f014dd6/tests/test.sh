#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import stat
import subprocess
import time
import unicodedata


def oracle_normalize(messages):
    payload = "\n".join(messages) + "\n"
    result = subprocess.run(
        ["/app/normalizer"],
        input=payload,
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=True,
    )
    outputs = result.stdout.splitlines()
    assert len(outputs) == len(messages), "Normalizer returned an unexpected number of lines"
    return outputs


def random_scalar(rng, wanted_prefixes):
    while True:
        cp = rng.randrange(0x110000)
        if 0xD800 <= cp <= 0xDFFF:
            continue
        ch = chr(cp)
        if ch in "\r\n":
            continue
        if unicodedata.category(ch)[0] in wanted_prefixes:
            return ch


def build_message_pool(rng, size):
    # Include known difficult scripts and Unicode cases, then add unpredictable
    # characters spanning the Unicode letter, number, mark, punctuation,
    # symbol, separator, and control/unassigned classes.
    significant = list(
        "AaZzİıſKΣσςЖжԱաԱԲ中文日本語한글" 
        "１２٣٤५६Ⅻ²①零一二三" 
        "ÉéÅåÞþŁł" 
        "𐐀𐐨𐒰𐓘"
    )
    removable = list(" !?.,:;_+-=()[]{}<>/@#$%^&*\t") + [
        "\u0301", "\u034f", "\u2003", "\u200b", "\u2028", "\u2060",
        "\u00ad", "\ufe0f", "😀", "©", "™", "\x00", "\x1f"
    ]

    for _ in range(220):
        significant.append(random_scalar(rng, {"L", "N"}))
    for _ in range(220):
        removable.append(random_scalar(rng, {"M", "P", "S", "Z", "C"}))

    pool = []
    for i in range(size):
        pieces = []
        for _ in range(rng.randint(5, 34)):
            if rng.random() < 0.58:
                ch = rng.choice(significant)
                # Exercise casing without using Python's result as the oracle.
                if rng.random() < 0.45:
                    ch = ch.swapcase()
                pieces.append(ch)
            else:
                pieces.append(rng.choice(removable))
        # Ensure every entry has at least one letter/number and make the pool
        # dependent on fresh verifier randomness.
        pieces.append(rng.choice(significant))
        pool.append("".join(pieces))
    return pool


def test_analyze_go_correctness_and_speed():
    go_file = "/home/user/analyze.go"
    assert os.path.exists(go_file), f"{go_file} not found"
    assert os.path.isfile(go_file), f"{go_file} is not a regular file"
    assert os.path.isfile("/app/normalizer"), "/app/normalizer not found"

    rng = random.Random(int.from_bytes(secrets.token_bytes(32), "big"))
    langs = ["en", "ja", "es", "fr"]
    pool = build_message_pool(rng, 1800)
    normalized_pool = oracle_normalize(pool)

    hidden_logs_path = "/tmp/hidden_logs.jsonl"
    num_records = 150000
    per_lang_counts = {lang: {} for lang in langs}
    observed_normalized = set()

    # Fresh, non-deterministic hot entries produce substantial duplicate groups,
    # while the long tail exercises many independent Unicode strings.
    hot = {lang: [rng.randrange(len(pool)) for _ in range(5)] for lang in langs}

    with open(hidden_logs_path, "w", encoding="utf-8") as f:
        for i in range(num_records):
            lang = rng.choice(langs)
            if rng.random() < 0.72:
                idx = rng.choice(hot[lang])
            else:
                idx = rng.randrange(len(pool))

            message = pool[idx]
            normalized = normalized_pool[idx]
            observed_normalized.add(normalized)
            counts = per_lang_counts[lang]
            counts[normalized] = counts.get(normalized, 0) + 1

            record = {"id": f"{secrets.token_hex(4)}-{i}", "lang": lang, "message": message}
            f.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")

    expected_summary = {
        "total_records": num_records,
        "unique_normalized_messages": len(observed_normalized),
        "top_message_per_lang": {},
    }
    for lang in langs:
        top_msg, top_count = max(per_lang_counts[lang].items(), key=lambda item: (item[1], item[0]))
        expected_summary["top_message_per_lang"][lang] = {
            "normalized_message": top_msg,
            "count": top_count,
        }

    try:
        subprocess.run(
            ["go", "build", "-o", "/tmp/analyze", go_file],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        assert False, f"Failed to compile {go_file}:\n{exc.stderr}"

    summary_path = "/home/user/summary.json"
    if os.path.exists(summary_path):
        os.remove(summary_path)

    # The legacy executable is available for reverse engineering, but not while
    # the submitted artifact is timed: the submitted program must implement the
    # normalization rather than invoke /app/normalizer on the hidden input.
    normalizer_path = "/app/normalizer"
    normalizer_mode = stat.S_IMODE(os.stat(normalizer_path).st_mode)
    with open(normalizer_path, "rb") as f:
        normalizer_bytes = f.read()
    os.remove(normalizer_path)

    try:
        start = time.monotonic()
        try:
            result = subprocess.run(
                ["/tmp/analyze", hidden_logs_path],
                check=True,
                capture_output=True,
                text=True,
                timeout=10,
            )
        except subprocess.CalledProcessError as exc:
            assert False, f"Execution of compiled Go program failed:\n{exc.stderr}"
        runtime = time.monotonic() - start
    finally:
        with open(normalizer_path, "wb") as f:
            f.write(normalizer_bytes)
        os.chmod(normalizer_path, normalizer_mode)

    assert os.path.exists(summary_path), f"{summary_path} not found. Did your program create it?"
    with open(summary_path, "r", encoding="utf-8") as f:
        try:
            output_summary = json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f"{summary_path} does not contain valid JSON: {exc}"

    assert output_summary == expected_summary, (
        f"Output summary does not match expected.\n"
        f"Output: {output_summary}\nExpected: {expected_summary}"
    )
    assert runtime <= 2.0, (
        f"Runtime {runtime:.2f}s exceeded threshold of 2.0s. "
        "The program is not fast enough (are you shelling out to the binary?)"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
