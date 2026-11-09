#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import secrets
import string
import subprocess

import pytest

OUTPUT = Path("/home/user/loc_clean.json")
INPUT = Path("/home/user/loc_raw.txt")
PROJECT = Path("/home/user/loc_processor")

EXPECTED_ORIGINAL = {
    "de-DE": {
        "FAREWELL": "Auf Wiedersehen",
        "GREETING": "Hallo Welt"
    },
    "es-ES": {
        "FAREWELL": "Adiós",
        "GREETING": "Hola Mundo"
    },
    "fr-FR": {
        "FAREWELL": "Au revoir",
        "GREETING": "Bonjour le monde"
    },
    "jp-JP": {
        "GREETING": "こんにちは"
    }
}


def test_loc_clean_json_exists():
    """Check if the loc_clean.json file was created."""
    assert OUTPUT.is_file(), f"Output file {OUTPUT} is missing. The Rust program may not have run or failed."


def test_loc_clean_json_content():
    """Check if the loc_clean.json file contains the correctly parsed and decoded data."""
    with OUTPUT.open("r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {OUTPUT} as JSON: {e}")

    assert data == EXPECTED_ORIGINAL, "The contents of loc_clean.json do not match the expected grouped and decoded translations."


def test_loc_clean_json_formatting():
    """Check if the output is pretty-printed with 2 spaces indentation and sorted keys."""
    raw_content = OUTPUT.read_text(encoding="utf-8")

    assert '  "de-DE": {' in raw_content or '  "es-ES": {' in raw_content, \
        "The JSON does not appear to be pretty-printed with 2 spaces of indentation."

    expected_raw = json.dumps(EXPECTED_ORIGINAL, indent=2, ensure_ascii=False)
    assert raw_content.strip() == expected_raw.strip(), \
        "The JSON formatting or sorting does not exactly match the expected pretty-printed output."


def _rust_sources():
    if not PROJECT.is_dir():
        return []
    return sorted(
        p for p in PROJECT.rglob("*.rs")
        if "target" not in p.parts and p.is_file() and p.stat().st_size > 0
    )


def _run_submission():
    sources = _rust_sources()
    assert PROJECT.is_dir(), "The required /home/user/loc_processor directory is missing."
    assert sources, "No non-empty Rust source file exists in /home/user/loc_processor."

    diagnostics = []
    manifests = sorted(PROJECT.rglob("Cargo.toml"), key=lambda p: (len(p.parts), str(p)))

    for manifest in manifests:
        if OUTPUT.exists():
            OUTPUT.unlink()
        try:
            result = subprocess.run(
                ["cargo", "run", "--quiet", "--manifest-path", str(manifest)],
                cwd=str(manifest.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
        except (subprocess.TimeoutExpired, OSError) as exc:
            diagnostics.append(f"{manifest}: {exc}")
            continue
        if result.returncode == 0 and OUTPUT.is_file():
            return
        diagnostics.append(f"{manifest}: exit {result.returncode}: {result.stderr[-1000:]}")

    preferred = sorted(
        sources,
        key=lambda p: (p.name != "main.rs", "src" not in p.parts, len(p.parts), str(p)),
    )
    binary = Path("/tmp/loc_processor_verifier_bin")
    for source in preferred:
        if binary.exists():
            binary.unlink()
        compile_result = subprocess.run(
            ["rustc", str(source), "-o", str(binary)],
            cwd=str(PROJECT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        if compile_result.returncode != 0:
            diagnostics.append(f"{source}: rustc failed: {compile_result.stderr[-1000:]}")
            continue

        if OUTPUT.exists():
            OUTPUT.unlink()
        try:
            run_result = subprocess.run(
                [str(binary)],
                cwd=str(PROJECT),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
        except (subprocess.TimeoutExpired, OSError) as exc:
            diagnostics.append(f"{source}: {exc}")
            continue
        if run_result.returncode == 0 and OUTPUT.is_file():
            return
        diagnostics.append(f"{source}: exit {run_result.returncode}: {run_result.stderr[-1000:]}")

    pytest.fail("Could not execute a Rust submission that generated loc_clean.json.\n" + "\n".join(diagnostics[-8:]))


def test_rust_program_processes_fresh_input():
    """Execute the Rust artifact against unpredictable input and validate its processing."""
    alphabet = string.ascii_uppercase
    suffix = ''.join(secrets.choice(alphabet) for _ in range(8))
    token = secrets.token_hex(8)

    records = [
        ("pt-BR", f"ZULU_{suffix}", f"Fim\\u0020{token}"),
        ("it-IT", f"ALPHA_{suffix}", f"Caf\\u00E9\\u0020{token}"),
        ("pt-BR", f"ALPHA_{suffix}", f"Ol\\u00E1\\u0020{token}"),
        ("ko-KR", f"MIDDLE_{suffix}", f"\\u4F60\\u597D\\u0020{token}"),
        ("it-IT", f"ZULU_{suffix}", f"Pi\\u00F9\\u0020{token}"),
    ]
    secrets.SystemRandom().shuffle(records)

    lines = ["unrelated startup log", "[malformed] {xx-XX} <BAD> : \"ignored\""]
    for index, (lang, key, encoded_value) in enumerate(records, start=10):
        lines.append(f'[2026-08-19 12:34:{index:02d}] {{{lang}}} <{key}> : "{encoded_value}"')
        lines.append(f"DEBUG record {index} ignored")
    lines.append("export complete")

    expected_unsorted = {}
    for lang, key, encoded_value in records:
        decoded = json.loads('"' + encoded_value + '"')
        expected_unsorted.setdefault(lang, {})[key] = decoded
    expected = {
        lang: {key: expected_unsorted[lang][key] for key in sorted(expected_unsorted[lang])}
        for lang in sorted(expected_unsorted)
    }
    expected_raw = json.dumps(expected, indent=2, ensure_ascii=False)

    original_input = INPUT.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None
    dynamic_raw = None
    try:
        INPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
        if OUTPUT.exists():
            OUTPUT.unlink()
        _run_submission()
        assert OUTPUT.is_file(), "Running the Rust program did not recreate loc_clean.json."
        dynamic_raw = OUTPUT.read_text(encoding="utf-8")
    finally:
        INPUT.write_bytes(original_input)
        if original_output is None:
            if OUTPUT.exists():
                OUTPUT.unlink()
        else:
            OUTPUT.write_bytes(original_output)

    try:
        dynamic_data = json.loads(dynamic_raw)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Rust program produced invalid JSON on fresh input: {exc}")

    assert dynamic_data == expected, \
        "The Rust program did not correctly extract, decode, group, and sort fresh input."
    assert dynamic_raw.strip() == expected_raw.strip(), \
        "Fresh output is not pretty-printed with 2-space indentation and sorted keys."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
