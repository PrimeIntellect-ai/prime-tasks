#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess

SOURCE = "/home/user/generate_i18n.cpp"
CSV = "/home/user/raw_translations.csv"
HEADER = "/home/user/i18n_data.h"
BINARY = "/tmp/generate_i18n_test"

ORIGINAL_CSV = """KEY,LANG,TEXT
BTN_OK,en,  OK  
BTN_OK,es,Aceptar
BTN_CANCEL,en,Cancel
BTN_CANCEL,es,  Cancelar  
GREETING,ja, こんにちは   世界 
GREETING,ja,こんにちは 世界 (override)
ERR_01,ar,خطأ
BTN_OK,es,  Aceptar  Definitivo 
MENU_FILE,en, File   Menu 
MENU_FILE,en,File Menu
"""

EXPECTED_ORIGINAL = """#ifndef I18N_DATA_H
#define I18N_DATA_H

#include <string>
#include <unordered_map>

struct I18nData {
    static std::unordered_map<std::string, std::unordered_map<std::string, std::string>> get_strings() {
        return {
            {"ar", {
                {"ERR_01", "خطأ"}
            }},
            {"en", {
                {"BTN_CANCEL", "Cancel"},
                {"BTN_OK", "OK"},
                {"MENU_FILE", "File Menu"}
            }},
            {"es", {
                {"BTN_CANCEL", "Cancelar"},
                {"BTN_OK", "Aceptar Definitivo"}
            }},
            {"ja", {
                {"GREETING", "こんにちは 世界 (override)"}
            }}
        };
    }
};

#endif // I18N_DATA_H"""


def normalize(content):
    return "\n".join(line.rstrip() for line in content.strip().splitlines())


def clean_text(text):
    return " ".join(part for part in text.strip(" ").split(" ") if part != "")


def expected_for_rows(rows):
    data = {}
    for key, lang, text in rows:
        data.setdefault(lang, {})[key] = clean_text(text)

    lines = [
        "#ifndef I18N_DATA_H",
        "#define I18N_DATA_H",
        "",
        "#include <string>",
        "#include <unordered_map>",
        "",
        "struct I18nData {",
        "    static std::unordered_map<std::string, std::unordered_map<std::string, std::string>> get_strings() {",
        "        return {",
    ]

    languages = sorted(data)
    for lang_index, lang in enumerate(languages):
        lines.append(f'            {{"{lang}", {{')
        keys = sorted(data[lang])
        for key_index, key in enumerate(keys):
            comma = "," if key_index + 1 < len(keys) else ""
            lines.append(f'                {{"{key}", "{data[lang][key]}"}}{comma}')
        comma = "," if lang_index + 1 < len(languages) else ""
        lines.append(f"            }}}}{comma}")

    lines.extend([
        "        };",
        "    }",
        "};",
        "",
        "#endif // I18N_DATA_H",
    ])
    return "\n".join(lines)


def write_csv(rows):
    with open(CSV, "w", encoding="utf-8", newline="\n") as f:
        f.write("KEY,LANG,TEXT\n")
        for key, lang, text in rows:
            f.write(f"{key},{lang},{text}\n")


def run_generator():
    if os.path.lexists(HEADER):
        os.remove(HEADER)
    result = subprocess.run(
        [BINARY], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"Generator exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(HEADER), f"File {HEADER} does not exist. Did you run your C++ program?"
    assert os.path.isfile(HEADER), f"Path {HEADER} is not a regular file."
    with open(HEADER, "r", encoding="utf-8") as f:
        return f.read()


def test_i18n_generator_and_final_header():
    assert os.path.exists(SOURCE), f"C++ source file {SOURCE} does not exist."
    assert stat.S_ISREG(os.stat(SOURCE).st_mode), f"Path {SOURCE} is not a regular file."

    with open(CSV, "w", encoding="utf-8", newline="\n") as f:
        f.write(ORIGINAL_CSV)

    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", BINARY],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {SOURCE} with g++ -std=c++17.\n"
        f"stdout:\n{compile_result.stdout}\nstderr:\n{compile_result.stderr}"
    )

    content = run_generator()
    content_normalized = normalize(content)
    expected_normalized = normalize(EXPECTED_ORIGINAL)
    assert content_normalized == expected_normalized, (
        f"The content of {HEADER} does not match the expected output. "
        "Please check indentation, sorting, deduplication, and text cleaning."
    )

    token = secrets.token_hex(8)
    lang_a = "aa" + token[:6]
    lang_b = "zz" + token[6:12]
    key_a = "ALPHA_" + token[:8].upper()
    key_b = "OMEGA_" + token[8:].upper()
    key_c = "MIDDLE_" + token[4:12].upper()
    rows = [
        (key_b, lang_b, "  first   世界  "),
        (key_c, lang_a, "  مرحبا   عالم  "),
        (key_a, lang_a, " Café   " + token + " "),
        (key_b, lang_b, " 最後   " + token + "  値 "),
        (key_a, lang_b, "  UTF8   こんにちは  "),
    ]
    write_csv(rows)
    dynamic_content = run_generator()
    assert normalize(dynamic_content) == normalize(expected_for_rows(rows)), (
        "The compiled generator did not correctly process a fresh CSV input; "
        "check CSV reading, ASCII-space cleaning, last-occurrence deduplication, sorting, and UTF-8 handling."
    )

    # Restore the required final input and output after the behavioral test.
    with open(CSV, "w", encoding="utf-8", newline="\n") as f:
        f.write(ORIGINAL_CSV)
    restored_content = run_generator()
    assert normalize(restored_content) == normalize(EXPECTED_ORIGINAL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
