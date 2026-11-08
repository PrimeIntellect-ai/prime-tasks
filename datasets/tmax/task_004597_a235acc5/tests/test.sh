#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import shutil
import string
import subprocess

import pytest


def test_locales_directory_exists():
    locales_dir = "/home/user/locales"
    assert os.path.exists(locales_dir), f"Directory {locales_dir} does not exist."
    assert os.path.isdir(locales_dir), f"Path {locales_dir} is not a directory."


def test_en_locale_content():
    en_path = "/home/user/locales/en.h"
    assert os.path.exists(en_path), f"File {en_path} does not exist."

    with open(en_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = [
        "#pragma once",
        "#include <string>",
        "namespace i18n_en {",
        'const std::string btn_cancel = "Cancel";',
        'const std::string btn_submit = "Submit Updated";',
        "}"
    ]
    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {en_path}"

    idx_cancel = content.find("btn_cancel")
    idx_submit = content.find("btn_submit")
    assert idx_cancel < idx_submit, "Keys in en.h are not sorted alphabetically."


def test_fr_locale_content():
    fr_path = "/home/user/locales/fr.h"
    assert os.path.exists(fr_path), f"File {fr_path} does not exist."

    with open(fr_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = [
        "#pragma once",
        "#include <string>",
        "namespace i18n_fr {",
        'const std::string btn_cancel = "Annuler";',
        'const std::string btn_submit = "Soumettre";',
        "}"
    ]
    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {fr_path}"

    idx_cancel = content.find("btn_cancel")
    idx_submit = content.find("btn_submit")
    assert idx_cancel < idx_submit, "Keys in fr.h are not sorted alphabetically."


def test_es_locale_content():
    es_path = "/home/user/locales/es.h"
    assert os.path.exists(es_path), f"File {es_path} does not exist."

    with open(es_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_lines = [
        "#pragma once",
        "#include <string>",
        "namespace i18n_es {",
        'const std::string success = "Éxito";',
        "}"
    ]
    for line in expected_lines:
        assert line in content, f"Expected line '{line}' not found in {es_path}"


def test_no_invalid_locales():
    locales_dir = "/home/user/locales"
    if os.path.exists(locales_dir):
        files = os.listdir(locales_dir)
        valid_files = {"en.h", "fr.h", "es.h"}
        for f in files:
            assert f in valid_files, f"Unexpected file {f} found in {locales_dir}. Invalid entries should be skipped."


def _cpp_literal(value):
    out = []
    for ch in value:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append("\\%03o" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def _random_lang(rng, used):
    while True:
        value = "".join(rng.choice(string.ascii_lowercase) for _ in range(2))
        if value not in used:
            used.add(value)
            return value


def _write_case(path, langs, invalid_lang, token):
    k1 = "alpha_" + token
    k2 = "middle_" + token
    k3 = "zed_" + token
    expected = {
        langs[0]: {
            k1: "replacement " + token,
            k2: 'quote " and slash \\ and tab\t café ' + token,
            k3: "last " + token,
        },
        langs[1]: {
            k1: "other " + token,
            k3: "value " + token,
        },
        langs[2]: {
            k2: "solo " + token,
        },
    }
    rows = [
        {"key": k3, "lang": langs[0], "text": expected[langs[0]][k3]},
        {"key": k1, "lang": langs[0], "text": "superseded " + token},
        {"key": k2, "lang": langs[0], "text": expected[langs[0]][k2]},
        {"key": k1, "lang": langs[1], "text": expected[langs[1]][k1]},
        {"key": k3, "lang": langs[1], "text": expected[langs[1]][k3]},
        {"key": k2, "lang": langs[2], "text": expected[langs[2]][k2]},
        {"key": k1, "lang": langs[0], "text": expected[langs[0]][k1]},
        {"key": "bad-key!", "lang": invalid_lang, "text": "must be skipped"},
        {"key": "valid_key", "lang": invalid_lang.upper(), "text": "must be skipped"},
        {"key": "missing_text", "lang": invalid_lang},
        {"key": "number_text", "lang": invalid_lang, "text": 123},
    ]
    with open(path, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
        f.write('{"key":"bad_unicode","lang":"%s","text":"bad \\u00ZZ"}\n' % invalid_lang)
        f.write("this is not json\n")
    return expected


def _check_headers(expected):
    locale_dir = "/home/user/locales"
    assert os.path.isdir(locale_dir), "Program did not create /home/user/locales"
    assert set(os.listdir(locale_dir)) == {lang + ".h" for lang in expected}, "Missing or unexpected locale headers"

    declaration = re.compile(r'^const std::string ([A-Za-z0-9_]+) = "(?:\\\\.|[^"\\\\])*";$')
    for lang, values in expected.items():
        path = os.path.join(locale_dir, lang + ".h")
        with open(path, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert len(lines) == len(values) + 4, f"Unexpected extra or missing content in {path}"
        assert lines[0] == "#pragma once"
        assert lines[1] == "#include <string>"
        assert lines[2] == f"namespace i18n_{lang} {{"
        assert lines[-1] == "}"
        declarations = lines[3:-1]
        matches = [declaration.fullmatch(line) for line in declarations]
        assert all(matches), f"Invalid declaration format in {path}"
        keys = [match.group(1) for match in matches]
        assert keys == sorted(values), f"Keys in {path} are not sorted or do not match valid input"

    checker = ["#include <string>"]
    for lang in sorted(expected):
        checker.append(f'#include "/home/user/locales/{lang}.h"')
    checker.append("int main() {")
    for lang, values in expected.items():
        for key, text in values.items():
            checker.append(f"if (i18n_{lang}::{key} != {_cpp_literal(text)}) return 1;")
    checker.append("return 0; }")
    with open("/tmp/check_generated.cpp", "w", encoding="utf-8") as f:
        f.write("\n".join(checker) + "\n")
    result = subprocess.run(
        ["g++", "-std=c++17", "-o", "/tmp/check_generated", "/tmp/check_generated.cpp"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, "Generated headers do not compile:\n" + result.stderr
    result = subprocess.run(["/tmp/check_generated"], timeout=10)
    assert result.returncode == 0, "Generated string values do not equal the parsed input text"


def test_z_source_compiles_and_handles_varied_input():
    source = "/home/user/generate_locales.cpp"
    assert os.path.isfile(source), f"Source file {source} does not exist"
    assert os.path.getsize(source) > 0, f"Source file {source} is empty"

    compiled = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-o", "/tmp/generate_locales_test", source],
        cwd="/home/user", stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=45
    )
    assert compiled.returncode == 0, "generate_locales.cpp does not compile:\n" + compiled.stderr

    input_path = "/home/user/translations.jsonl"
    with open(input_path, "rb") as f:
        original_input = f.read()
    rng = random.SystemRandom()
    try:
        for _ in range(2):
            token = "".join(rng.choice(string.ascii_lowercase + string.digits) for _ in range(12))
            used = {"en", "fr", "es"}
            langs = [_random_lang(rng, used) for _ in range(3)]
            invalid_lang = _random_lang(rng, used)
            expected = _write_case(input_path, langs, invalid_lang, token)
            shutil.rmtree("/home/user/locales", ignore_errors=True)
            run = subprocess.run(
                ["/tmp/generate_locales_test"], cwd="/home/user",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
            )
            assert run.returncode == 0, "Compiled generator failed:\n" + run.stderr
            _check_headers(expected)
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
