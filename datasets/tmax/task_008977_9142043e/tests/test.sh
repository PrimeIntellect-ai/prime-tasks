#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess

import pytest

HOME = "/home/user"
TRANS = "/home/user/translations"
SOURCE = "/home/user/process_translations.cpp"
SCRIPT = "/home/user/run_pipeline.sh"
EXECUTABLE = "/home/user/process_translations"


def run_checked(command, timeout=30):
    result = subprocess.run(
        command,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_pipeline_on_original_fixture():
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} is missing."
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    for path in (EXECUTABLE, f"{TRANS}/merged.tsv", f"{TRANS}/stats.txt"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    run_checked([SCRIPT])
    assert os.path.isfile(EXECUTABLE), (
        f"Running {SCRIPT} did not create {EXECUTABLE}."
    )
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            f"{EXECUTABLE} is not a compiled native executable."
        )


def test_merged_tsv_content():
    """Check if merged.tsv exists and matches the expected content."""
    filepath = "/home/user/translations/merged.tsv"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = [
        "key\ten\tfr\tja\tes",
        "greeting\tHello\tBonjour\tこんにちは\tHola",
        "farewell\tGoodbye\tAu revoir\t\tAdiós",
        "apple\tApple\t\tりんご\tManzana"
    ]
    expected_content = "\n".join(expected_lines)

    actual_lines = content.splitlines()
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in merged.tsv, found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in merged.tsv does not match.\nExpected: {repr(expected)}\nActual: {repr(actual)}"


def test_stats_txt_content():
    """Check if stats.txt exists and matches the expected content."""
    filepath = "/home/user/translations/stats.txt"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = [
        "en: 100%, 17",
        "fr: 66%, 16",
        "ja: 66%, 8",
        "es: 100%, 16"
    ]

    actual_lines = content.splitlines()
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in stats.txt, found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in stats.txt does not match.\nExpected: {repr(expected)}\nActual: {repr(actual)}"


def test_run_pipeline_sh():
    """Check if run_pipeline.sh exists and is executable."""
    filepath = "/home/user/run_pipeline.sh"
    assert os.path.isfile(filepath), f"Script {filepath} is missing."
    assert os.access(filepath, os.X_OK), f"Script {filepath} is not executable."


def test_cron_schedule_txt():
    """Check if cron_schedule.txt contains the correct cron expression."""
    filepath = "/home/user/cron_schedule.txt"
    assert os.path.isfile(filepath), f"File {filepath} is missing."

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read().strip()

    pattern = r"^\s*30\s+2\s+\*\s+\*\s+(0|7|sun|sunday)\s+/home/user/run_pipeline\.sh\s*$"
    assert re.match(pattern, content, re.IGNORECASE), f"Content of {filepath} does not match the expected cron expression for 2:30 AM on Sunday running /home/user/run_pipeline.sh. Found: {content}"


def test_pipeline_handles_unseen_fixture_and_cpp_runs_independently():
    alphabet = string.ascii_lowercase + string.digits
    token = "".join(secrets.choice(alphabet) for _ in range(12))
    keys = [f"key_{token}_{i}" for i in range(5)]

    values = {
        "en": {
            keys[0]: f"North🙂{token}",
            keys[1]: "Café界",
            keys[2]: f"Delta{token}",
            keys[3]: "naïve🚀",
            keys[4]: "終わり",
        },
        "fr": {
            keys[4]: f"fin{token}",
            keys[0]: "Bonjouré",
            keys[2]: "Ça🙂",
        },
        "ja": {
            keys[3]: "ロケット🚀",
            keys[1]: f"世界{token}",
        },
        "es": {
            keys[1]: "Adiós",
            keys[4]: "Mañana界",
            keys[0]: f"Hola{token}",
            keys[3]: "Cohete🙂",
        },
    }

    original_files = {}
    for lang in ("en", "fr", "ja", "es"):
        path = f"{TRANS}/{lang}.csv"
        with open(path, "rb") as f:
            original_files[path] = f.read()

    def write_csv(lang, ordered_keys):
        with open(f"{TRANS}/{lang}.csv", "w", encoding="utf-8", newline="") as f:
            f.write("key,text\n")
            for key in ordered_keys:
                f.write(f"{key},{values[lang][key]}\n")

    def expected_outputs():
        merged = ["key\ten\tfr\tja\tes"]
        for key in keys:
            merged.append("\t".join([
                key,
                values["en"].get(key, ""),
                values["fr"].get(key, ""),
                values["ja"].get(key, ""),
                values["es"].get(key, ""),
            ]))

        stats = []
        total = len(keys)
        for lang in ("en", "fr", "ja", "es"):
            translated = sum(1 for key in keys if key in values[lang])
            chars = sum(len(values[lang][key]) for key in keys if key in values[lang])
            stats.append(f"{lang}: {(translated * 100) // total}%, {chars}")
        return "\n".join(merged), "\n".join(stats)

    def assert_generated_outputs():
        expected_merged, expected_stats = expected_outputs()
        with open(f"{TRANS}/merged.tsv", "r", encoding="utf-8") as f:
            actual_merged = f.read().strip()
        with open(f"{TRANS}/stats.txt", "r", encoding="utf-8") as f:
            actual_stats = f.read().strip()
        assert actual_merged == expected_merged
        assert actual_stats == expected_stats

    try:
        write_csv("en", keys)
        write_csv("fr", [keys[4], keys[0], keys[2]])
        write_csv("ja", [keys[3], keys[1]])
        write_csv("es", [keys[1], keys[4], keys[0], keys[3]])

        for path in (EXECUTABLE, f"{TRANS}/merged.tsv", f"{TRANS}/stats.txt"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        # The submitted shell script must compile and run the pipeline itself.
        run_checked([SCRIPT])
        assert os.path.isfile(EXECUTABLE)
        assert os.access(EXECUTABLE, os.X_OK)
        with open(EXECUTABLE, "rb") as f:
            assert f.read(4) == b"\x7fELF"
        assert_generated_outputs()

        # Independently compile and execute the submitted C++ source so that a
        # script which merely hardcodes or generates the files cannot pass.
        verified_executable = f"/tmp/process_translations_verified_{token}"
        run_checked(["g++", "-std=c++17", SOURCE, "-o", verified_executable])
        for path in (f"{TRANS}/merged.tsv", f"{TRANS}/stats.txt"):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        run_checked([verified_executable])
        assert_generated_outputs()
    finally:
        for path, data in original_files.items():
            with open(path, "wb") as f:
                f.write(data)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
