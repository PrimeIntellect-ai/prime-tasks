#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile


def poly_hash(value):
    modulus = 1000000009
    power = 1
    result = 0
    for byte in value.encode("ascii"):
        result = (result + byte * power) % modulus
        power = (power * 31) % modulus
    return result


def expected_dedup(records):
    selected = {}
    for key, source in records:
        if source not in selected or key < selected[source]:
            selected[source] = key
    return [(poly_hash(source), key, source) for source, key in selected.items()]


def parse_output(output):
    records = []
    for line in output.splitlines():
        if not line:
            continue
        fields = line.split("\t", 2)
        assert len(fields) == 3, f"Malformed output line: {line!r}"
        try:
            hash_value = int(fields[0])
        except ValueError:
            raise AssertionError(f"Hash is not an integer in line: {line!r}")
        records.append((hash_value, fields[1], fields[2]))
    return records


def run_program(path, records):
    input_data = "".join(f"{key}\t{source}\n" for key, source in records)
    result = subprocess.run(
        [path], input=input_data, capture_output=True, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"{path} failed with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )
    return parse_output(result.stdout)


def test_cron_schedule():
    cron_file = "/home/user/cron_schedule.txt"
    assert os.path.isfile(cron_file), f"Cron schedule file {cron_file} is missing."
    with open(cron_file, "r") as f:
        content = f.read().strip()
    expected_cron = "0 2 * * * /home/user/pipeline.sh"
    assert content == expected_cron, (
        f"Cron schedule is incorrect. Expected {expected_cron!r}, got {content!r}."
    )


def test_cpp_source_exists():
    cpp_file = "/home/user/src/dedup.cpp"
    assert os.path.isfile(cpp_file), f"C++ source file {cpp_file} is missing."


def test_pipeline_execution_and_original_output():
    pipeline_script = "/home/user/pipeline.sh"
    report_file = "/home/user/deduped_report.tsv"

    assert os.path.isfile(pipeline_script), f"Pipeline script {pipeline_script} is missing."
    assert os.access(pipeline_script, os.X_OK), f"Pipeline script {pipeline_script} is not executable."

    if os.path.exists(report_file):
        os.remove(report_file)

    result = subprocess.run([pipeline_script], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"Pipeline script failed with return code {result.returncode}.\nStderr: {result.stderr}"
    )
    assert os.path.isfile(report_file), f"Output report {report_file} was not created by the pipeline."

    with open(report_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "138118029\terr_network\tNetwork error",
        "139556272\tbil_invoice\tInvoice",
        "188282004\tbil_cancel_sub\tCancel",
        "421396301\tbil_submit_payment\tSubmit",
        "627196884\terr_auth\tAuthentication failed",
        "878036087\tlbl_welcome\tWelcome back!",
    ]
    assert len(lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in report, got {len(lines)}."
    )
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, (
            f"Line {i + 1} mismatch.\nExpected: {expected}\nGot:      {actual}"
        )


def test_cpp_compiles_and_handles_runtime_generated_input():
    source = "/home/user/src/dedup.cpp"
    build_dir = tempfile.mkdtemp(prefix="verify_dedup_build_")
    executable = os.path.join(build_dir, "dedup")
    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++17", source, "-o", executable],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "dedup.cpp does not compile as C++17.\n"
            f"Stderr: {compile_result.stderr}"
        )

        token = secrets.token_hex(12)
        records = [
            ("z_key_" + token, "Repeated value " + token),
            ("a_key_" + token, "Repeated value " + token),
            ("middle_" + token, "Value with spaces " + token),
            ("punct_" + token, "Punctuation!?-" + token),
            ("other_" + token, "Another source " + token),
        ]
        random.SystemRandom().shuffle(records)
        actual = run_program(executable, records)
        expected = expected_dedup(records)
        assert sorted(actual) == sorted(expected), (
            f"Compiled dedup output is incorrect.\nExpected: {sorted(expected)!r}\n"
            f"Got: {sorted(actual)!r}"
        )
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_pipeline_on_runtime_generated_locales_and_compiled_binary():
    pipeline_script = "/home/user/pipeline.sh"
    locales = "/home/user/locales"
    report = "/home/user/deduped_report.tsv"
    binary = "/home/user/bin/dedup"
    backup_root = tempfile.mkdtemp(prefix="locales_backup_")
    backup = os.path.join(backup_root, "locales")
    shutil.copytree(locales, backup)

    try:
        shutil.rmtree(locales)
        os.makedirs(locales)

        while True:
            token = secrets.token_hex(10)
            records = [
                ("z_duplicate_" + token, "Shared source " + token),
                ("a_duplicate_" + token, "Shared source " + token),
                ("alpha_" + token, "Alpha runtime " + token),
                ("beta_" + token, "Beta value with spaces " + token),
                ("gamma_" + token, "Gamma!? " + token),
            ]
            expected = expected_dedup(records)
            if len({item[0] for item in expected}) == len(expected):
                break

        with open(os.path.join(locales, "alpha.json"), "w") as f:
            json.dump(dict(records[:3]), f)
        with open(os.path.join(locales, "beta.json"), "w") as f:
            json.dump(dict(records[3:]), f)
        with open(os.path.join(locales, "ignored.txt"), "w") as f:
            json.dump({"must_not_appear": "Non JSON decoy " + token}, f)

        if os.path.exists(report):
            os.remove(report)
        if os.path.lexists(binary):
            if os.path.isdir(binary) and not os.path.islink(binary):
                shutil.rmtree(binary)
            else:
                os.remove(binary)

        result = subprocess.run(
            [pipeline_script], capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, (
            f"Pipeline failed on runtime-generated locale files.\nStderr: {result.stderr}"
        )
        assert os.path.isfile(report), "Pipeline did not create deduped_report.tsv."
        assert os.path.isfile(binary), "Pipeline did not create /home/user/bin/dedup."
        assert os.access(binary, os.X_OK), "Compiled dedup artifact is not executable."
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", "/home/user/bin/dedup is not a compiled ELF executable."

        with open(report, "r") as f:
            actual = parse_output(f.read())
        expected_sorted = sorted(expected, key=lambda item: item[0])
        assert actual == expected_sorted, (
            "Pipeline report is incorrect for runtime-generated locale data.\n"
            f"Expected: {expected_sorted!r}\nGot: {actual!r}"
        )

        binary_probe = [
            ("z_probe_" + token, "Probe duplicate " + token),
            ("a_probe_" + token, "Probe duplicate " + token),
            ("single_probe_" + token, "Probe single " + token),
        ]
        binary_actual = run_program(binary, binary_probe)
        binary_expected = expected_dedup(binary_probe)
        assert sorted(binary_actual) == sorted(binary_expected), (
            "The binary produced by the pipeline does not implement the required deduplication."
        )
    finally:
        shutil.rmtree(locales, ignore_errors=True)
        shutil.copytree(backup, locales)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
