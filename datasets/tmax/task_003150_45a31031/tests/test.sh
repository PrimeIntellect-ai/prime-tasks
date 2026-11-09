#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import os
import secrets
import subprocess
import unicodedata

import pytest

CLEAN_DIR = "/var/opt/corpora/clean"
EVIL_DIR = "/var/opt/corpora/evil"
SCRIPT_PATH = "/home/user/cleaner.py"
PACKAGE_DIR = "/app/unicodenorm-0.2.1"


def test_unicodenorm_installed_and_configuration_fixed():
    try:
        import unicodenorm
        assert importlib.metadata.version("unicodenorm") == "0.2.1"
        assert unicodenorm.is_malicious("\u202Eevil") is True, (
            "unicodenorm.is_malicious did not return True for a known malicious string."
        )
        assert unicodenorm.is_malicious("ordinary text") is False
    except ImportError:
        pytest.fail("unicodenorm package is not installed or cannot be imported.")
    except Exception as exc:
        pytest.fail(f"unicodenorm installation or is_malicious failed: {exc}")

    setup_path = os.path.join(PACKAGE_DIR, "setup.py")
    assert os.path.isfile(setup_path), "The vendored package setup.py is missing."
    with open(setup_path, "r", encoding="utf-8") as setup_file:
        setup_text = setup_file.read()
    assert "typing_extensions>=9999.0" not in setup_text, (
        "The deliberately broken dependency constraint was not fixed."
    )


def line_must_be_dropped(line):
    import unicodenorm

    if unicodenorm.is_malicious(line):
        return True

    if line.endswith("\r\n"):
        content = line[:-2]
    elif line.endswith("\n") or line.endswith("\r"):
        content = line[:-1]
    else:
        content = line

    def is_punctuation_or_symbol(character):
        return unicodedata.category(character)[0] in ("P", "S")

    if len(content) < 20:
        count = sum(is_punctuation_or_symbol(character) for character in content)
        return count * 2 > len(content)

    flags = [is_punctuation_or_symbol(character) for character in content]
    count = sum(flags[:20])
    if count > 10:
        return True
    for index in range(20, len(flags)):
        count += flags[index] - flags[index - 20]
        if count > 10:
            return True
    return False


def expected_output(input_data):
    text = input_data.decode("utf-8")
    lines = text.splitlines(keepends=True)
    return "".join(line for line in lines if not line_must_be_dropped(line)).encode("utf-8")


def run_cleaner(input_data):
    result = subprocess.run(
        [SCRIPT_PATH],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"cleaner exited with status {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    return result.stdout


def test_script_exists_and_is_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_shipped_corpora_follow_the_specification():
    clean_files = [
        os.path.join(CLEAN_DIR, name)
        for name in os.listdir(CLEAN_DIR)
        if os.path.isfile(os.path.join(CLEAN_DIR, name))
    ]
    evil_files = [
        os.path.join(EVIL_DIR, name)
        for name in os.listdir(EVIL_DIR)
        if os.path.isfile(os.path.join(EVIL_DIR, name))
    ]
    assert clean_files and evil_files

    for path in clean_files:
        with open(path, "rb") as corpus_file:
            input_data = corpus_file.read()
        output = run_cleaner(input_data)
        assert output == input_data, f"Clean corpus file was modified: {path}"
        assert output == expected_output(input_data)

    for path in evil_files:
        with open(path, "rb") as corpus_file:
            input_data = corpus_file.read()
        output = run_cleaner(input_data)
        assert output == expected_output(input_data), (
            f"Corpus file was not filtered according to the stated thresholds: {path}"
        )

    fixture_path = os.path.join(EVIL_DIR, "malicious.txt")
    if os.path.isfile(fixture_path):
        with open(fixture_path, "rb") as fixture_file:
            fixture_output = run_cleaner(fixture_file.read())
        assert fixture_output == b"short!@#$%\n", (
            "A short line with exactly 50% punctuation must be preserved."
        )


def test_generated_unpredictable_inputs():
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    punctuation = "!@#$%^&*()_+=?"
    random_letters = lambda count: "".join(secrets.choice(alphabet) for _ in range(count))

    cases = [
        random_letters(37) + "\n",
        punctuation[:5] + random_letters(5) + "\n",
        punctuation[:6] + random_letters(4) + "\n",
        punctuation[:10] + random_letters(10) + "\r\n",
        punctuation[:11] + random_letters(9) + "\n",
        random_letters(secrets.randbelow(12)) + punctuation[:11] + random_letters(30) + "\n",
        random_letters(8) + "\u2067" + random_letters(8) + "\n",
        "正常なテキスト" + random_letters(12) + "。\n",
    ]
    secrets.SystemRandom().shuffle(cases)
    input_data = "".join(cases).encode("utf-8")
    assert run_cleaner(input_data) == expected_output(input_data)

    final_line_without_newline = (random_letters(13) + punctuation[:6]).encode("utf-8")
    assert run_cleaner(final_line_without_newline) == expected_output(final_line_without_newline)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
