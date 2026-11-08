#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

DEPLOY_INPUTS = []


def test_fstab_entry():
    fstab_path = "/home/user/fstab_entry.txt"
    assert os.path.isfile(fstab_path), f"Expected {fstab_path} to exist."

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    expected = "UUID=1234-5678 /home/user/metrics_data xfs defaults,noatime 0 0"
    normalized_content = re.sub(r'\s+', ' ', content)
    assert normalized_content == expected, f"fstab entry does not match expected format. Got: {content}"


def test_deploy_script_and_execution():
    global DEPLOY_INPUTS

    script_path = "/home/user/deploy.sh"
    source_path = "/home/user/proxy.c"
    fixture_path = "/home/user/test_metrics.txt"
    binary_path = "/home/user/proxy_bin"
    log_path = "/home/user/metrics_data/metrics.log"
    mail_path = "/home/user/mail.mbox"

    assert os.path.isfile(script_path), f"Expected {script_path} to exist."
    assert os.access(script_path, os.X_OK), f"Expected {script_path} to be executable."
    assert os.path.isfile(source_path), f"Expected {source_path} to exist."

    with open(source_path, "r") as f:
        original_source = f.read()
    with open(fixture_path, "rb") as f:
        original_fixture = f.read()

    token = secrets.token_hex(16)
    marker_path = f"/tmp/proxy_was_run_{token}"
    marker_code = (
        f'\n    FILE *_verifier_marker_{token} = fopen("{marker_path}", "w");\n'
        f'    if (_verifier_marker_{token}) {{ fputs("{token}", _verifier_marker_{token}); '
        f'fclose(_verifier_marker_{token}); }}\n'
    )
    main_match = re.search(r'int\s+main\s*\([^)]*\)\s*\{', original_source)
    assert main_match, "proxy.c does not contain a recognizable main function."
    instrumented_source = original_source[:main_match.end()] + marker_code + original_source[main_match.end():]

    DEPLOY_INPUTS = [
        f"INFO dynamic-cpu-{token}",
        f"ERROR dynamic-error-{token}",
        f"WARN dynamic-latency-{token}",
    ]
    fixture_lines = [
        "INFO CPU usage is at 45%",
        "ERROR Memory leak detected in worker process",
        "WARN Latency spiked to 200ms",
    ] + DEPLOY_INPUTS

    os.makedirs("/home/user/metrics_data", exist_ok=True)
    for path in (binary_path, log_path, mail_path, marker_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    try:
        with open(source_path, "w") as f:
            f.write(instrumented_source)
        with open(fixture_path, "w") as f:
            f.write("\n".join(fixture_lines) + "\n")

        result = subprocess.run([script_path], capture_output=True, text=True, timeout=30)
    finally:
        with open(source_path, "w") as f:
            f.write(original_source)
        with open(fixture_path, "wb") as f:
            f.write(original_fixture)

    assert result.returncode == 0, f"deploy.sh failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert os.path.isfile(binary_path), "deploy.sh did not create /home/user/proxy_bin."
    assert os.access(binary_path, os.X_OK), "proxy_bin is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "proxy_bin is not a compiled ELF executable."

    assert os.path.isfile(marker_path), "deploy.sh did not run the aggregator compiled from proxy.c."
    with open(marker_path, "r") as f:
        assert f.read() == token, "The executed aggregator did not produce the expected runtime marker."

    assert os.path.isfile(log_path), "deploy.sh did not create metrics.log."
    with open(log_path, "r") as f:
        deployed_log = f.read()
    for payload in DEPLOY_INPUTS:
        assert payload in deployed_log, f"deploy.sh did not pipe the dynamic test metric through proxy_bin: {payload}"


def test_mail_mbox_appended():
    mail_path = "/home/user/mail.mbox"
    assert os.path.isfile(mail_path), f"Expected {mail_path} to exist."

    with open(mail_path, "r") as f:
        content = f.read()

    expected_headers = "To: observability-alerts@local.dev\nSubject: Deployment successful"
    expected_body = "The metrics proxy has been deployed."
    expected_message = expected_headers + "\n\n" + expected_body

    assert expected_headers in content, "mail.mbox is missing the expected headers."
    assert expected_body in content, "mail.mbox is missing the expected body."
    assert expected_message in content, "mail.mbox does not contain the required header/body formatting."


def test_metrics_log_output():
    log_path = "/home/user/metrics_data/metrics.log"
    assert os.path.isfile(log_path), f"Expected {log_path} to exist after running deploy.sh."

    with open(log_path, "r") as f:
        lines = f.readlines()

    assert len(lines) >= 3, "metrics.log should contain at least 3 lines of output."

    error_line_present = any("ERROR Memory leak detected" in line for line in lines)
    assert error_line_present, "The ERROR line was dropped. The bug in proxy.c was not fixed correctly."

    for payload in DEPLOY_INPUTS:
        matching = [line for line in lines if payload in line]
        assert len(matching) == 1, f"Expected exactly one logged line for dynamic metric: {payload}"
        assert re.match(r'^\[(.*?) (CET|CEST)\]', matching[0]), (
            f"Timestamp does not contain the Europe/Zurich timezone for: {matching[0].strip()}"
        )

    for line in lines[-3:]:
        match = re.match(r'^\[(.*?) (CET|CEST)\]', line)
        assert match, f"Timestamp in log line does not contain the Europe/Zurich timezone (CET/CEST). Line: {line.strip()}"


def test_proxy_source_itself_is_fixed():
    source_path = "/home/user/proxy.c"
    check_binary = f"/tmp/proxy_source_check_{secrets.token_hex(8)}"
    log_path = "/home/user/metrics_data/metrics.log"
    token = secrets.token_hex(16)
    inputs = [
        f"INFO source-info-{token}",
        f"ERROR source-error-{token}",
        f"WARN source-warn-{token}",
    ]

    compile_result = subprocess.run(
        ["gcc", source_path, "-o", check_binary], capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"proxy.c does not compile: {compile_result.stderr}"

    old_log = None
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            old_log = f.read()
    try:
        try:
            os.remove(log_path)
        except FileNotFoundError:
            pass
        env = os.environ.copy()
        env["TZ"] = "Europe/Zurich"
        run_result = subprocess.run(
            [check_binary], input="\n".join(inputs) + "\n", capture_output=True,
            text=True, env=env, timeout=30
        )
        assert run_result.returncode == 0, f"Aggregator built from proxy.c failed: {run_result.stderr}"
        assert os.path.isfile(log_path), "Aggregator built from proxy.c did not create metrics.log."
        with open(log_path, "r") as f:
            lines = f.readlines()
        for payload in inputs:
            matching = [line for line in lines if payload in line]
            assert len(matching) == 1, f"proxy.c failed to log dynamic input: {payload}"
            assert re.match(r'^\[(.*?) (CET|CEST)\]', matching[0]), (
                f"proxy.c produced a timestamp outside Europe/Zurich: {matching[0].strip()}"
            )
    finally:
        try:
            os.remove(check_binary)
        except FileNotFoundError:
            pass
        if old_log is not None:
            with open(log_path, "wb") as f:
                f.write(old_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
