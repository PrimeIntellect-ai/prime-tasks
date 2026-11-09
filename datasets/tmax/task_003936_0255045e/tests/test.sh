#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import tempfile
import uuid

APP_DIR = "/app/net-sniff-processor-v1.2.0"
BINARY_PATH = "/home/user/redactor"
SOURCE_PATH = "/home/user/redactor.go"


def test_makefile_fixed_and_builds():
    binary_path = os.path.join(APP_DIR, "net-sniff")

    if os.path.exists(binary_path):
        os.remove(binary_path)

    result = subprocess.run(
        ["make", "build"],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    assert result.returncode == 0, (
        f"make build failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert os.path.isfile(binary_path), (
        f"make build succeeded but {binary_path} was not created."
    )


def test_redactor_binary_exists():
    assert os.path.isfile(BINARY_PATH), (
        f"The redactor binary at {BINARY_PATH} does not exist."
    )
    assert os.access(BINARY_PATH, os.X_OK), (
        f"The redactor binary at {BINARY_PATH} is not executable."
    )


def test_redactor_source_exists_and_binary_is_go():
    assert os.path.isfile(SOURCE_PATH), (
        f"The required Go source at {SOURCE_PATH} does not exist."
    )
    assert os.path.getsize(SOURCE_PATH) > 0, "redactor.go is empty."

    info = subprocess.run(
        ["go", "version", "-m", BINARY_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert info.returncode == 0 and "go1" in info.stdout, (
        "The installed redactor is not a Go executable.\n"
        f"Stdout: {info.stdout}\nStderr: {info.stderr}"
    )

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "redactor-from-source")
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, SOURCE_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert build.returncode == 0, (
            "redactor.go does not compile.\n"
            f"Stdout: {build.stdout}\nStderr: {build.stderr}"
        )

        args = [
            "--probe=unchanged",
            "prefix-AKIAa1B2c3D4e5F6g7H8-suffix",
            "note=PASSWORD=source-build-secret tail",
        ]
        expected = sanitize(args)
        result, report, marker = invoke_through_target(rebuilt, args)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == marker
        assert report["argv"] == [], "The rebuilt redactor passed data as target argv."
        assert json.loads(report["stdin"]) == expected


def sanitize(args):
    # Apply the specified substitutions globally to every argument.
    output = []
    for value in args:
        value = re.sub(r"AKIA[A-Za-z0-9]{16}", "[REDACTED]", value)
        value = re.sub(r"PASSWORD=[^ ]+", "[REDACTED]", value)
        output.append(value)
    return output


def invoke_through_target(binary, args):
    with tempfile.TemporaryDirectory() as td:
        marker = "TARGET-RAN-" + uuid.uuid4().hex
        report_path = os.path.join(td, "target-report.json")
        target_path = os.path.join(td, "target.py")

        with open(target_path, "w", encoding="utf-8") as target:
            target.write("#!/usr/bin/env python3\n")
            target.write("import json, os, sys\n")
            target.write("data = sys.stdin.read()\n")
            target.write("with open(os.environ['REPORT_PATH'], 'w', encoding='utf-8') as f:\n")
            target.write("    json.dump({'argv': sys.argv[1:], 'stdin': data}, f)\n")
            target.write("sys.stdout.write(os.environ['TARGET_MARKER'])\n")
        os.chmod(target_path, os.stat(target_path).st_mode | stat.S_IXUSR)

        env = os.environ.copy()
        env["TARGET_SCRIPT"] = target_path
        env["REPORT_PATH"] = report_path
        env["TARGET_MARKER"] = marker

        result = subprocess.run(
            [binary] + args,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )

        assert os.path.isfile(report_path), (
            "The configured TARGET_SCRIPT was not executed."
        )
        with open(report_path, "r", encoding="utf-8") as report_file:
            report = json.load(report_file)
        return result, report, marker


def run_redactor_on_corpus(corpus_dir):
    results = {}

    for filename in sorted(os.listdir(corpus_dir)):
        filepath = os.path.join(corpus_dir, filename)
        if not os.path.isfile(filepath):
            continue

        with open(filepath, "r", encoding="utf-8") as corpus_file:
            args = [line.strip() for line in corpus_file if line.strip()]

        result, report, marker = invoke_through_target(BINARY_PATH, args)
        results[filename] = {
            "args": args,
            "stdout": result.stdout.strip(),
            "stderr": result.stderr.strip(),
            "returncode": result.returncode,
            "target_argv": report["argv"],
            "target_stdin": report["stdin"],
            "marker": marker,
        }

    return results


def test_clean_corpus():
    results = run_redactor_on_corpus("/app/tests/corpus/clean")

    failed_files = []
    for filename, data in results.items():
        if data["returncode"] != 0:
            failed_files.append(f"{filename} (crashed)")
            continue
        if data["stdout"] != data["marker"]:
            failed_files.append(f"{filename} (did not relay target output)")
            continue
        if data["target_argv"] != []:
            failed_files.append(f"{filename} (passed packet data in target argv)")
            continue

        try:
            output_json = json.loads(data["target_stdin"])
        except json.JSONDecodeError:
            failed_files.append(f"{filename} (invalid JSON on target stdin)")
            continue

        if output_json != data["args"]:
            failed_files.append(f"{filename} (modified clean arguments)")

    assert not failed_files, (
        f"{len(failed_files)} of {len(results)} clean files modified or failed: "
        + ", ".join(failed_files)
    )


def test_evil_corpus():
    results = run_redactor_on_corpus("/app/tests/corpus/evil")

    akia_pattern = re.compile(r"AKIA[A-Z0-9]{16}")
    password_pattern = re.compile(r"PASSWORD=[^ ]+")

    failed_files = []
    for filename, data in results.items():
        if data["returncode"] != 0:
            failed_files.append(f"{filename} (crashed)")
            continue
        if data["stdout"] != data["marker"]:
            failed_files.append(f"{filename} (did not execute target correctly)")
            continue
        if data["target_argv"] != []:
            failed_files.append(f"{filename} (passed secrets in target argv)")
            continue

        try:
            output_json = json.loads(data["target_stdin"])
        except json.JSONDecodeError:
            failed_files.append(f"{filename} (invalid JSON on target stdin)")
            continue

        leaked = any(
            not isinstance(item, str)
            or akia_pattern.search(item)
            or password_pattern.search(item)
            for item in output_json
        )
        if leaked:
            failed_files.append(f"{filename} (failed to redact secret)")
            continue

        if output_json != sanitize(data["args"]):
            failed_files.append(f"{filename} (did not preserve and redact exactly)")

    assert not failed_files, (
        f"{len(failed_files)} of {len(results)} evil files bypassed redaction or failed: "
        + ", ".join(failed_files)
    )


def test_dynamic_redaction_and_target_execution():
    nonce = uuid.uuid4().hex
    api_one = "AKIA" + nonce[:16]
    api_two = "AKIA" + nonce[16:32].upper()
    password = "pw-" + uuid.uuid4().hex

    args = [
        "--source=203.0.113.7",
        f"before:{api_one}:after",
        f"--payload=alpha PASSWORD={password} trailing text",
        f"--mixed={api_two},PASSWORD=second-{nonce}",
        "--innocent=AKIA-too-short",
        "PASSWORDISH=must-stay",
        f"two={api_one}/{api_two}",
    ]
    expected = sanitize(args)

    result, report, marker = invoke_through_target(BINARY_PATH, args)
    assert result.returncode == 0, (
        f"redactor failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert result.stdout.strip() == marker, (
        "Output did not come from the configured TARGET_SCRIPT."
    )
    assert report["argv"] == [], (
        "Sanitized data must be sent on stdin, not as TARGET_SCRIPT arguments."
    )

    try:
        actual = json.loads(report["stdin"])
    except json.JSONDecodeError as exc:
        raise AssertionError(f"TARGET_SCRIPT stdin was not valid JSON: {exc}")

    assert actual == expected, (
        f"Incorrect dynamic redaction. Expected {expected!r}, got {actual!r}"
    )
    assert "[REDACTED]" in report["stdin"]
    assert api_one not in report["stdin"]
    assert api_two not in report["stdin"]
    assert password not in report["stdin"]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
