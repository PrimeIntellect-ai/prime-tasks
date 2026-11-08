#!/bin/bash
mkdir -p /logs/verifier /home/user/server_data

# Replace any pre-existing HTTP server with one serving the intended directory.
pkill -f '[p]ython3 -m http.server 8080' >/dev/null 2>&1 || true
sleep 0.2
(cd /home/user/server_data && exec python3 -m http.server 8080 >/tmp/l10n_http_server.log 2>&1) &
SERVER_PID=$!
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT
sleep 0.5

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import pathlib
import secrets
import shutil
import subprocess

PIPELINE = pathlib.Path("/home/user/pipeline.sh")
OUTPUT = pathlib.Path("/home/user/clean_l10n.jsonl")
PROJECT = pathlib.Path("/home/user/l10n_cleaner")
RAW = pathlib.Path("/home/user/raw_data")
SERVER = pathlib.Path("/home/user/server_data")


def read_jsonl(path):
    actual = []
    with open(path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError as e:
                raise AssertionError(f"Line {line_num} in {path} is not valid JSON: {e}")
    return actual


def assert_output(expected):
    assert OUTPUT.is_file(), f"File {OUTPUT} does not exist."
    actual = read_jsonl(OUTPUT)
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} records in {OUTPUT}, got {len(actual)}."
    )
    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act == exp, (
            f"Mismatch at line {i + 1} in {OUTPUT}:\nExpected: {exp}\nActual: {act}"
        )


def write_csv(path, records):
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "locale", "msg_id", "translation"])
        for record in records:
            writer.writerow([
                record["timestamp"], record["locale"], record["msg_id"],
                record["translation"],
            ])


def expected_records(*groups):
    result = []
    for group in groups:
        for record in group:
            result.append({
                "timestamp": int(record["timestamp"]),
                "locale": record["locale"],
                "msg_id": record["msg_id"],
                "translation": record["translation"].replace("\n", " ").replace("\r", " ").strip(),
            })
    return sorted(result, key=lambda item: item["timestamp"])


def run_as_user(command, cwd="/home/user", timeout=300):
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", *command],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


def test_pipeline_script_exists():
    path = "/home/user/pipeline.sh"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_clean_l10n_jsonl_exists():
    path = "/home/user/clean_l10n.jsonl"
    assert os.path.isfile(path), f"File {path} does not exist."


def test_clean_l10n_jsonl_content():
    expected = [
        {"timestamp": 1670000001, "locale": "fr_FR", "msg_id": "bye", "translation": "Au revoir"},
        {"timestamp": 1670000002, "locale": "de_DE", "msg_id": "error", "translation": "Fehler aufgetreten bitte warten"},
        {"timestamp": 1670000005, "locale": "es_ES", "msg_id": "welcome", "translation": "Hola Mundo"},
        {"timestamp": 1670000010, "locale": "en_US", "msg_id": "info", "translation": "Update successful"},
    ]
    assert_output(expected)


def test_pipeline_and_rust_artifact_on_derived_inputs():
    assert PIPELINE.is_file(), f"File {PIPELINE} does not exist."
    assert PIPELINE.stat().st_size > 0, "pipeline.sh is empty."
    assert (PROJECT / "Cargo.toml").is_file(), "Rust Cargo.toml is missing."
    assert (PROJECT / "src" / "main.rs").is_file(), "Rust src/main.rs is missing."

    token = secrets.token_hex(8)
    base = 1800000000 + secrets.randbelow(1000000)
    data1 = [
        {"timestamp": base + 40, "locale": "es_MX", "msg_id": f"welcome_{token}", "translation": f"  Hola,{token}\nMundo  "},
        {"timestamp": base + 3, "locale": "fr_CA", "msg_id": f"quote_{token}", "translation": f'Il a dit "oui" {token}'},
    ]
    data2 = [
        {"timestamp": base + 20, "locale": "de_AT", "msg_id": f"error_{token}", "translation": f"Fehler\naufgetreten\n{token}"},
        {"timestamp": base + 70, "locale": "ja_JP", "msg_id": f"info_{token}", "translation": f"  更新成功 {token}  "},
    ]
    write_csv(SERVER / "data1.csv", data1)
    write_csv(SERVER / "data2.csv", data2)
    os.chmod(SERVER / "data1.csv", 0o644)
    os.chmod(SERVER / "data2.csv", 0o644)

    # Exercise the required validation checkpoint with one remote file absent.
    missing = SERVER / "data2.csv.missing"
    os.replace(SERVER / "data2.csv", missing)
    shutil.rmtree(RAW, ignore_errors=True)
    OUTPUT.unlink(missing_ok=True)
    try:
        failed = run_as_user(["/bin/bash", str(PIPELINE)], timeout=120)
        assert failed.returncode != 0, (
            "pipeline.sh succeeded even though data2.csv was unavailable.\n" + failed.stdout
        )
    finally:
        os.replace(missing, SERVER / "data2.csv")

    # Run the complete pipeline as the non-root user on unpredictable input.
    shutil.rmtree(RAW, ignore_errors=True)
    shutil.rmtree(PROJECT / "target", ignore_errors=True)
    OUTPUT.unlink(missing_ok=True)
    completed = run_as_user(["/bin/bash", str(PIPELINE)], timeout=300)
    assert completed.returncode == 0, "pipeline.sh failed:\n" + completed.stdout

    assert (RAW / "data1.csv").is_file(), "pipeline did not download data1.csv."
    assert (RAW / "data2.csv").is_file(), "pipeline did not download data2.csv."
    assert (RAW / "data1.csv").read_bytes() == (SERVER / "data1.csv").read_bytes(), "Downloaded data1.csv differs from the served file."
    assert (RAW / "data2.csv").read_bytes() == (SERVER / "data2.csv").read_bytes(), "Downloaded data2.csv differs from the served file."
    assert_output(expected_records(data1, data2))

    # Independently exercise the submitted Rust project so a shell-only or
    # hardcoded pipeline cannot satisfy the behavioral output check.
    token2 = secrets.token_hex(8)
    base2 = base + 2000000
    direct1 = [
        {"timestamp": base2 + 91, "locale": "pt_BR", "msg_id": f"late_{token2}", "translation": f"  linha um\nlinha dois {token2}  "},
        {"timestamp": base2 + 1, "locale": "en_GB", "msg_id": f"early_{token2}", "translation": f"comma, quote \" {token2}"},
    ]
    direct2 = [
        {"timestamp": base2 + 44, "locale": "ko_KR", "msg_id": f"middle_{token2}", "translation": f"첫째\n둘째\n{token2}"},
    ]
    for entry in RAW.iterdir():
        if entry.is_file():
            entry.unlink()
    write_csv(RAW / "first.csv", direct1)
    write_csv(RAW / "second.csv", direct2)
    OUTPUT.unlink(missing_ok=True)

    cargo_run = run_as_user(
        ["/usr/bin/cargo", "run", "--release", "--manifest-path", str(PROJECT / "Cargo.toml")],
        cwd=str(PROJECT),
        timeout=300,
    )
    assert cargo_run.returncode == 0, "Submitted Rust project failed to run:\n" + cargo_run.stdout
    assert_output(expected_records(direct1, direct2))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
