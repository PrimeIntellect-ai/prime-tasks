#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
import tempfile
from pathlib import Path

import pytest

VENDOR_DIR = "/app/vendor/libcsvquery"
LIB_PATH = os.path.join(VENDOR_DIR, "libcsvquery.a")
SANITIZER = "/home/user/sanitizer"
SOURCE = "/home/user/sanitizer.cpp"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def test_vendor_compilation_and_archive_contents():
    # Force a real rebuild rather than accepting a pre-existing placeholder.
    for name in ("csvquery.o", "libcsvquery.a"):
        try:
            os.remove(os.path.join(VENDOR_DIR, name))
        except FileNotFoundError:
            pass

    result = run(["make", "-C", VENDOR_DIR])
    assert result.returncode == 0, (
        f"make failed in {VENDOR_DIR}:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert os.path.isfile(LIB_PATH), f"Expected static library {LIB_PATH} was not created."

    listing = run(["ar", "t", LIB_PATH])
    assert listing.returncode == 0, f"{LIB_PATH} is not a valid archive: {listing.stderr}"
    members = [line.strip() for line in listing.stdout.splitlines() if line.strip()]
    assert members and any(member.endswith(".o") for member in members), (
        "libcsvquery.a contains no object file"
    )

    symbols = run(["nm", "-C", "--defined-only", LIB_PATH])
    assert symbols.returncode == 0, f"Could not inspect {LIB_PATH}: {symbols.stderr}"
    assert "csvquery::is_valid_schema" in symbols.stdout, (
        "libcsvquery.a does not define csvquery::is_valid_schema"
    )

    # Exercise the archive through its public header and expected implementation.
    with tempfile.TemporaryDirectory(prefix="vendor_probe_") as td:
        probe_cpp = os.path.join(td, "probe.cpp")
        probe_bin = os.path.join(td, "probe")
        Path(probe_cpp).write_text(
            '#include "csvquery.h"\n'
            'int main() {\n'
            '  return csvquery::is_valid_schema("orders") &&\n'
            '         !csvquery::is_valid_schema("") ? 0 : 1;\n'
            '}\n'
        )
        built = run([
            "g++", "-std=c++17", "-I", VENDOR_DIR,
            probe_cpp, LIB_PATH, "-o", probe_bin,
        ])
        assert built.returncode == 0, (
            f"A program could not link against libcsvquery.a:\n{built.stderr}"
        )
        exercised = run([probe_bin])
        assert exercised.returncode == 0, "libcsvquery.a failed its API probe"


def test_sanitizer_executable_exists():
    assert os.path.isfile(SANITIZER), f"Sanitizer executable {SANITIZER} is missing."
    assert os.access(SANITIZER, os.X_OK), f"Sanitizer {SANITIZER} is not executable."
    with open(SANITIZER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer must be a compiled executable"


def test_sanitizer_source_builds_and_uses_vendor_library():
    assert os.path.isfile(SOURCE), f"Sanitizer source {SOURCE} is missing."
    obj = "/tmp/sanitizer_verifier.o"
    rebuilt = "/tmp/sanitizer_verifier"

    compiled = run([
        "g++", "-std=c++17", "-O0", "-I", VENDOR_DIR,
        "-c", SOURCE, "-o", obj,
    ])
    assert compiled.returncode == 0, f"sanitizer.cpp does not compile:\n{compiled.stderr}"

    undefined = run(["nm", "-uC", obj])
    assert undefined.returncode == 0, f"Could not inspect sanitizer object: {undefined.stderr}"
    assert "csvquery::is_valid_schema" in undefined.stdout, (
        "sanitizer.cpp does not use libcsvquery"
    )

    linked = run(["g++", obj, LIB_PATH, "-o", rebuilt])
    assert linked.returncode == 0, (
        f"sanitizer.cpp does not link against libcsvquery.a:\n{linked.stderr}"
    )


def test_sanitizer_clean_corpus():
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory {clean_dir} missing."
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.json')]
    assert len(clean_files) > 0, "No clean corpus files found."

    failed_files = []
    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = run([SANITIZER, filepath], timeout=5)
        if result.returncode != 0 or result.stdout != "CLEAN\n":
            failed_files.append((filename, result.stdout.strip(), result.stderr.strip()))

    if failed_files:
        details = "\n".join(
            f"{f}: stdout='{out}', stderr='{err}'" for f, out, err in failed_files
        )
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified/rejected:\n{details}")


def test_sanitizer_evil_corpus():
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory {evil_dir} missing."
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert len(evil_files) > 0, "No evil corpus files found."

    failed_files = []
    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = run([SANITIZER, filepath], timeout=5)
        if result.returncode != 0 or result.stdout != "EVIL\n":
            failed_files.append((filename, result.stdout.strip(), result.stderr.strip()))

    if failed_files:
        details = "\n".join(
            f"{f}: stdout='{out}', stderr='{err}'" for f, out, err in failed_files
        )
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed:\n{details}")


def violates(value):
    if isinstance(value, list):
        return any(violates(item) for item in value)
    if not isinstance(value, dict):
        return False

    if "$where" in value or "$javascript" in value:
        return True

    collection = value.get("collection")
    if isinstance(collection, str) and ("." in collection or "/" in collection):
        return True

    lookup = value.get("$lookup")
    if isinstance(lookup, str):
        if "." in lookup or "/" in lookup or lookup.startswith(("private_", "system_")):
            return True
    elif isinstance(lookup, dict):
        for key in ("from", "collection"):
            target = lookup.get(key)
            if isinstance(target, str) and (
                "." in target or "/" in target or
                target.startswith(("private_", "system_"))
            ):
                return True

    match = value.get("$match")
    if isinstance(match, dict):
        for key in ("from", "collection"):
            target = match.get(key)
            if isinstance(target, str) and target.startswith(("private_", "system_")):
                return True

    return any(violates(item) for item in value.values())


def test_randomized_hidden_pipeline_cases():
    # Names, contents, order, and paths are generated only after the agent has run.
    cases = []
    for _ in range(10):
        token = secrets.token_hex(10)
        safe_collection = "public_" + token
        private_collection = "private_" + token
        system_collection = "system_" + token

        cases.extend([
            {"collection": safe_collection, "pipeline": [
                {"$match": {"status": "private_" + token, "note": "../ordinary/value"}},
                {"$lookup": {"from": "shared_" + token, "as": "rows"}},
            ]},
            {"metadata": {"$whereish": "safe", "collection_label": "a/b"},
             "pipeline": [{"$group": {"_id": "$region"}}]},
            {"collection": "segment/" + token, "pipeline": []},
            {"outer": [{"collection": "segment." + token}]},
            {"pipeline": [{"$lookup": {"from": "../" + token, "as": "x"}}]},
            {"pipeline": [{"$lookup": {"from": private_collection, "as": "x"}}]},
            {"pipeline": [{"$lookup": {"collection": system_collection, "as": "x"}}]},
            {"pipeline": [{"$match": {"collection": private_collection}}]},
            {"pipeline": [{"$match": {"from": system_collection}}]},
            {"deep": {"items": [{"payload": {"$where": "return true"}}]}},
            {"deep": [{"more": {"$javascript": "doBadThings()"}}]},
        ])

    secrets.SystemRandom().shuffle(cases)
    binaries = [SANITIZER, "/tmp/sanitizer_verifier"]

    with tempfile.TemporaryDirectory(prefix="pipeline_inputs_") as td:
        for case in cases:
            expected = "EVIL\n" if violates(case) else "CLEAN\n"
            path = os.path.join(td, secrets.token_hex(16) + ".json")
            with open(path, "w") as f:
                json.dump(case, f, separators=(",", ":"))

            for binary in binaries:
                result = run([binary, path], timeout=5)
                assert result.returncode == 0, (
                    f"{binary} exited {result.returncode} for generated input; "
                    f"stderr={result.stderr!r}"
                )
                assert result.stdout == expected, (
                    f"{binary} returned {result.stdout!r}, expected {expected!r} "
                    f"for generated pipeline {case!r}"
                )
                assert result.stderr == "", f"{binary} produced unexpected stderr output"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
