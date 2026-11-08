#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import secrets
import subprocess
import textwrap
import pytest

HOME = "/home/user"
LOCALES = os.path.join(HOME, "locales")


def run_checked(command, **kwargs):
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
        **kwargs,
    )
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {command}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def setup_module(module):
    processor = os.path.join(HOME, "processor.go")
    script = os.path.join(HOME, "run_pipeline.sh")

    assert os.path.isfile(processor), f"{processor} does not exist."

    # Independently ensure the submitted Go artifact compiles.
    build_path = f"/tmp/processor-verifier-{secrets.token_hex(6)}"
    run_checked(["go", "build", "-o", build_path, processor], cwd=HOME)

    # Inspect the parsed Go imports, rather than accepting a mention in a comment.
    import_checker = "/tmp/check_csv_import.go"
    with open(import_checker, "w", encoding="utf-8") as f:
        f.write(textwrap.dedent(r'''
            package main
            import (
                "go/parser"
                "go/token"
                "os"
                "strconv"
            )
            func main() {
                target := os.Getenv("TARGET_GO_FILE")
                parsed, err := parser.ParseFile(token.NewFileSet(), target, nil, 0)
                if err != nil { os.Exit(2) }
                for _, spec := range parsed.Imports {
                    path, err := strconv.Unquote(spec.Path.Value)
                    if err == nil && path == "encoding/csv" { return }
                }
                os.Exit(3)
            }
        '''))
    env = os.environ.copy()
    env["TARGET_GO_FILE"] = processor
    run_checked(["go", "run", import_checker], cwd=HOME, env=env)

    suffix = secrets.token_hex(8)
    locale = f"qa_{suffix}"
    source_rows = [
        (f"plain_{suffix}", f"Source plain {suffix}"),
        (f"multiline_{suffix}", "Source %s first line\nsecond line %d and %f"),
        (f"repeated_{suffix}", "%s then %s, %d, %f and %f"),
        (f"bad_s_{suffix}", "%s and %s"),
        (f"bad_d_{suffix}", "%d"),
        (f"bad_f_{suffix}", "%f and %f"),
    ]
    target_rows = [
        (f"plain_{suffix}", f"Traducción naïve 東京 {suffix}"),
        (f"multiline_{suffix}", f"Cible %s {suffix}\ndeuxième ligne %d puis %f"),
        (f"repeated_{suffix}", "Un %s, deux %s, nombre %d, réels %f/%f"),
        (f"bad_s_{suffix}", "Seulement %s"),
        (f"bad_d_{suffix}", "Aucun nombre ici"),
        (f"bad_f_{suffix}", "Seulement %f"),
    ]

    source_path = os.path.join(LOCALES, "en_US.csv")
    with open(source_path, "a", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerows(source_rows)

    target_path = os.path.join(LOCALES, locale + ".csv")
    with open(target_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "translation"])
        writer.writerows(target_rows)

    # Remove all preexisting answers so the pipeline must regenerate them.
    for pattern in (os.path.join(HOME, "output_*.json"), os.path.join(HOME, "errors_*.log")):
        for path in glob.glob(pattern):
            os.remove(path)

    assert os.path.isfile(script), f"{script} does not exist."
    assert os.access(script, os.X_OK), f"{script} is not executable."
    run_checked([script], cwd=HOME)

    module.dynamic_locale = locale
    module.dynamic_expected = {
        target_rows[0][0]: len(target_rows[0][1].encode("utf-8")),
        target_rows[1][0]: len(target_rows[1][1].encode("utf-8")),
        target_rows[2][0]: len(target_rows[2][1].encode("utf-8")),
    }
    module.dynamic_errors = {target_rows[3][0], target_rows[4][0], target_rows[5][0]}


def test_run_pipeline_exists_and_executable():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_dynamic_discovered_locale():
    json_path = f"/home/user/output_{dynamic_locale}.json"
    log_path = f"/home/user/errors_{dynamic_locale}.log"
    assert os.path.isfile(json_path), f"{json_path} does not exist."
    assert os.path.isfile(log_path), f"{log_path} does not exist."

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    assert data == dynamic_expected, "Dynamic locale output has incorrect byte lengths or validation."

    with open(log_path, "r", encoding="utf-8") as f:
        errors = f.read().strip().splitlines()
    assert len(errors) == len(dynamic_errors), "Dynamic error log contains the wrong number of entries."
    assert set(errors) == dynamic_errors, "Dynamic error log contains incorrect IDs."


def test_fr_fr_errors_log():
    log_path = "/home/user/errors_fr_FR.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()
    assert "bad_placeholder" in content, f"Expected 'bad_placeholder' in {log_path}."
    assert len(content) == 1, f"Expected exactly 1 error in {log_path}, got {len(content)}."


def test_es_es_errors_log():
    log_path = "/home/user/errors_es_ES.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist."
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()
    assert "count" in content, f"Expected 'count' in {log_path}."
    assert len(content) == 1, f"Expected exactly 1 error in {log_path}, got {len(content)}."


def test_fr_fr_output_json():
    json_path = "/home/user/output_fr_FR.json"
    assert os.path.isfile(json_path), f"{json_path} does not exist."
    with open(json_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} contains invalid JSON.")

    expected = {
        "welcome": len("Bienvenue, %s!".encode('utf-8')),
        "multiline": len("Ligne 1\nLigne 2".encode('utf-8')),
        "count": len("Vous avez %d articles".encode('utf-8'))
    }
    assert data == expected, f"Content of {json_path} does not match expected byte lengths."


def test_es_es_output_json():
    json_path = "/home/user/output_es_ES.json"
    assert os.path.isfile(json_path), f"{json_path} does not exist."
    with open(json_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} contains invalid JSON.")

    expected = {
        "welcome": len("¡Bienvenido, %s!".encode('utf-8')),
        "multiline": len("Línea 1\nLínea 2".encode('utf-8')),
        "bad_placeholder": len("Puntuación: %f".encode('utf-8'))
    }
    assert data == expected, f"Content of {json_path} does not match expected byte lengths."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
