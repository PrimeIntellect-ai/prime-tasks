#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

LOC = "/home/user/loc"
SCRIPT = os.path.join(LOC, "compile_loc.sh")
BASE = os.path.join(LOC, "en_base.txt")
RAW = os.path.join(LOC, "fr_raw.txt")
FINAL = os.path.join(LOC, "fr_final.txt")
PLACEHOLDER = re.compile(r"\[[A-Za-z0-9_]+\]")


def run_script():
    result = subprocess.run(
        ["bash", SCRIPT],
        cwd=LOC,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"compile_loc.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def derive_expected(base_text, raw_text):
    base = {}
    for line in base_text.splitlines():
        key, value = line.split("=", 1)
        base[key] = value

    selected = {}
    for line in raw_text.splitlines():
        key, value = line.split("=", 1)
        if key not in base or key in selected:
            continue
        if len(PLACEHOLDER.findall(value)) == len(PLACEHOLDER.findall(base[key])):
            selected[key] = value

    return "\n".join(
        f"{key}={selected.get(key, base[key])}" for key in sorted(base)
    )


def test_01_compile_loc_exists():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."


def test_02_fr_final_content_after_execution():
    run_script()
    assert os.path.isfile(FINAL), f"The final output file {FINAL} does not exist."

    expected_content = """ERR_001=L'équation [eq_name] manque de variable [x].
ERR_002=Le déterminant de la matrice est zéro.
ERR_003=Value [val] exceeds limit [max].
ERR_004=L'algorithme [alg] a échoué à l'étape [step_id] avec le code [err_code].
ERR_005=Convergence not reached after [n] iterations.
ERR_006=Erreur de syntaxe dans l'expression [expr]."""

    with open(FINAL, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == expected_content, (
        f"The content of {FINAL} is incorrect.\n"
        f"Expected:\n{expected_content}\nGot:\n{content}"
    )


def test_03_dynamic_pipeline():
    backups = {}
    for path in (BASE, RAW, FINAL):
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()
        else:
            backups[path] = None

    token = secrets.token_hex(8).upper()
    keys = {
        name: f"DYN_{token}_{name}" for name in ("A", "B", "C", "D", "E")
    }
    unknown = f"DYN_{token}_UNKNOWN"

    # Deliberately unsorted base data exercises output sorting. The raw data
    # exercises unknown keys, invalid entries followed by valid ones, duplicate
    # valid translations, placeholder-count validation, and English fallback.
    base_lines = [
        f"{keys['D']}=English [one] [two_2] [three].",
        f"{keys['B']}=English text without placeholders.",
        f"{keys['E']}=Missing translation for [item].",
        f"{keys['A']}=English [left] and [right_9].",
        f"{keys['C']}=English value [original_name].",
    ]
    raw_lines = [
        f"{unknown}=Unknown translation.",
        f"{keys['A']}=Invalid translation with only [one].",
        f"{keys['B']}=Première traduction sans paramètre.",
        f"{keys['A']}=Première valide [alpha] et [beta_7].",
        f"{keys['A']}=Deuxième valide [gamma] et [delta].",
        f"{keys['C']}=Nom différent mais même compte [replacement].",
        f"{keys['D']}=Seulement [one] et [two].",
        f"{keys['B']}=Deuxième traduction sans paramètre.",
        f"{keys['B']}=Première traduction sans paramètre.",
    ]
    base_text = "\n".join(base_lines) + "\n"
    raw_text = "\n".join(raw_lines) + "\n"
    expected = derive_expected(base_text, raw_text)

    try:
        with open(BASE, "w", encoding="utf-8", newline="\n") as f:
            f.write(base_text)
        with open(RAW, "w", encoding="utf-8", newline="\n") as f:
            f.write(raw_text)
        if os.path.lexists(FINAL):
            os.remove(FINAL)

        run_script()
        assert os.path.isfile(FINAL), "The script did not generate fr_final.txt."
        with open(FINAL, "r", encoding="utf-8") as f:
            actual_lines = f.read().splitlines()

        assert actual_lines == expected.splitlines(), (
            "compile_loc.sh failed on dynamically generated inputs.\n"
            f"Expected:\n{expected}\nGot:\n" + "\n".join(actual_lines)
        )
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.lexists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
