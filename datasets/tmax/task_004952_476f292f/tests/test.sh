#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import stat
import subprocess
import tempfile
import uuid


def test_vendored_package_run_sh():
    package_dir = "/app/smtpd-stub-0.0.1"
    run_sh_path = os.path.join(package_dir, "run.sh")
    assert os.path.isfile(run_sh_path), f"File {run_sh_path} is missing."
    assert os.access(run_sh_path, os.X_OK), f"File {run_sh_path} is not executable."

    # Preserve the original behavioral checks against the shipped server.
    env = os.environ.copy()
    env["SMTP_PORT"] = "8888"
    res_custom = subprocess.run(
        [run_sh_path], cwd=package_dir, env=env, capture_output=True, text=True, timeout=10
    )
    assert "8888" in res_custom.stdout or "8888" in res_custom.stderr, \
        "run.sh did not pass the custom SMTP_PORT (8888) to server.py."

    env.pop("SMTP_PORT", None)
    res_default = subprocess.run(
        [run_sh_path], cwd=package_dir, env=env, capture_output=True, text=True, timeout=10
    )
    assert "2525" in res_default.stdout or "2525" in res_default.stderr, \
        "run.sh did not use the default port 2525 when SMTP_PORT is unset."

    # Instrument server.py and verify that run.sh really invokes it with values
    # chosen at test time, rather than merely printing expected port strings.
    server_path = os.path.join(package_dir, "server.py")
    assert os.path.isfile(server_path), f"File {server_path} is missing."
    original = pathlib.Path(server_path).read_bytes()
    original_mode = stat.S_IMODE(os.stat(server_path).st_mode)

    probe = b'''#!/usr/bin/python3\nimport json, os, sys\nwith open(os.environ["RUN_PROBE_LOG"], "a", encoding="utf-8") as f:\n    f.write(json.dumps(sys.argv[1:]) + "\\n")\n'''

    with tempfile.TemporaryDirectory(prefix="run-sh-probe-") as td:
        log_path = os.path.join(td, "calls.jsonl")
        try:
            pathlib.Path(server_path).write_bytes(probe)
            os.chmod(server_path, 0o755)

            custom_port = str(30000 + (uuid.uuid4().int % 20000))
            cases = [(custom_port, custom_port), (None, "2525"), ("", "2525")]
            for supplied, expected in cases:
                pathlib.Path(log_path).write_text("", encoding="utf-8")
                case_env = os.environ.copy()
                case_env["RUN_PROBE_LOG"] = log_path
                if supplied is None:
                    case_env.pop("SMTP_PORT", None)
                else:
                    case_env["SMTP_PORT"] = supplied

                result = subprocess.run(
                    [run_sh_path], cwd=package_dir, env=case_env,
                    capture_output=True, text=True, timeout=10
                )
                assert result.returncode == 0, \
                    f"run.sh failed for SMTP_PORT={supplied!r}: {result.stderr}"
                calls = [json.loads(line) for line in pathlib.Path(log_path).read_text(encoding="utf-8").splitlines()]
                assert calls == [["--port", expected]], \
                    f"server.py was not invoked exactly once with --port {expected}: {calls!r}"
        finally:
            pathlib.Path(server_path).write_bytes(original)
            os.chmod(server_path, original_mode)


def test_email_classifier_adversarial():
    classifier = "/home/user/classify_email"
    assert os.path.isfile(classifier), f"Classifier script {classifier} is missing."
    assert os.access(classifier, os.X_OK), f"Classifier script {classifier} is not executable."

    # Preserve the original corpus checks.
    evil_dir = "/app/emails/evil/"
    clean_dir = "/app/emails/clean/"
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    assert len(evil_files) > 0, "No evil corpus files found."
    assert len(clean_files) > 0, "No clean corpus files found."

    evil_bypassed = []
    for ef in evil_files:
        if subprocess.run([classifier, ef], timeout=10).returncode != 1:
            evil_bypassed.append(os.path.basename(ef))

    clean_modified = []
    for cf in clean_files:
        if subprocess.run([classifier, cf], timeout=10).returncode != 0:
            clean_modified.append(os.path.basename(cf))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    assert not errors, " | ".join(errors)

    # Exercise newly generated files at unpredictable paths and derive expected
    # results directly from the rules in the instruction.
    samples = [
        "From: a@example.com\n\nNo subject here.\n",
        "Subject: One\nFrom: a@example.com\n\nHello\n",
        "sUbJeCt: One\nFrom: a@example.com\n\nHello\n",
        " Subject: indented\n Subject: also indented\n\nHello\n",
        "Subject: One\nFrom: a@example.com\n\nx-admin-bypass: 1\n",
        "Subject: One\nX-Admin-Bypass:  1\n\nHello\n",
        "Subject: One\nsubject: Two\n\nDuplicate\n",
        "SUBJECT: One\nFrom: a@example.com\nSubject: Two\n\nDuplicate\n",
        "From: a@example.com\n\nX-Admin-Bypass: 1\n",
        "Subject: One\n\nprefix X-Admin-Bypass: 1 suffix\n",
        "Subject: One\r\nSUBJECT: Two\r\n\r\nCRLF duplicate\r\n",
    ]

    def expected_status(content):
        subject_count = sum(1 for line in content.splitlines() if line.lower().startswith("subject:"))
        return 1 if subject_count > 1 or "X-Admin-Bypass: 1" in content else 0

    with tempfile.TemporaryDirectory(prefix="generated-mail-") as td:
        for content in samples:
            path = os.path.join(td, f"{uuid.uuid4().hex}.eml")
            pathlib.Path(path).write_bytes(content.encode("utf-8"))
            result = subprocess.run([classifier, path], capture_output=True, timeout=10)
            expected = expected_status(content)
            assert result.returncode == expected, \
                f"Classifier returned {result.returncode}, expected {expected}, for generated content {content!r}"


def test_mail_profile_setup():
    profile = "/home/user/mail_profile.sh"
    assert os.path.isfile(profile), f"Profile script {profile} is missing."

    # Preserve the original variable checks.
    cmd_vars = f"source {profile} && echo $SMTP_PORT && echo $MAIL_CLASSIFIER"
    res_vars = subprocess.run(["bash", "-c", cmd_vars], capture_output=True, text=True, timeout=10)
    assert res_vars.returncode == 0, "Failed to source mail_profile.sh."
    lines = res_vars.stdout.strip().split("\n")
    assert len(lines) >= 2, "Expected output for SMTP_PORT and MAIL_CLASSIFIER."
    assert lines[0] == "8025", f"Expected SMTP_PORT to be 8025, got {lines[0]}."
    assert lines[1] == "/home/user/classify_email", \
        f"Expected MAIL_CLASSIFIER to be /home/user/classify_email, got {lines[1]}."

    # Confirm these are exported, not merely shell-local variables.
    export_check = subprocess.run(
        ["bash", "-c", 'source "$1" >/dev/null && test "$(printenv SMTP_PORT)" = 8025 && test "$(printenv MAIL_CLASSIFIER)" = /home/user/classify_email', "bash", profile],
        capture_output=True, text=True, timeout=10
    )
    assert export_check.returncode == 0, "SMTP_PORT and MAIL_CLASSIFIER must both be exported."

    # Preserve the original function-definition assertion.
    cmd_func = f"source {profile} && declare -f start_tunnel"
    res_func = subprocess.run(["bash", "-c", cmd_func], capture_output=True, text=True, timeout=10)
    assert res_func.returncode == 0, "Function start_tunnel is not defined in mail_profile.sh."
    func_body = res_func.stdout.replace("\\\n", " ")
    expected_cmd = "ssh -f -N -L 8025:localhost:25 mailadmin@mail.local -i /home/user/.ssh/mail_rsa"
    assert expected_cmd in func_body or expected_cmd.replace("  ", " ") in func_body.replace("  ", " "), \
        "start_tunnel function does not contain the exact expected ssh command."

    # Invoke the function with a PATH-injected ssh recorder and verify the exact
    # argument vector used by the command.
    with tempfile.TemporaryDirectory(prefix="tunnel-probe-") as td:
        fake_ssh = os.path.join(td, "ssh")
        log_path = os.path.join(td, f"ssh-{uuid.uuid4().hex}.log")
        pathlib.Path(fake_ssh).write_text(
            '#!/bin/sh\n: "${SSH_LOG:?}"\nprintf "%s\\0" "$@" > "$SSH_LOG"\n',
            encoding="utf-8"
        )
        os.chmod(fake_ssh, 0o755)
        invoke_env = os.environ.copy()
        invoke_env["PATH"] = td + os.pathsep + invoke_env.get("PATH", "")
        invoke_env["SSH_LOG"] = log_path
        invoked = subprocess.run(
            ["bash", "-c", 'source "$1" && start_tunnel', "bash", profile],
            env=invoke_env, capture_output=True, text=True, timeout=10
        )
        assert invoked.returncode == 0, f"start_tunnel failed when invoked: {invoked.stderr}"
        assert os.path.isfile(log_path), "start_tunnel did not execute ssh."
        raw = pathlib.Path(log_path).read_bytes()
        actual_args = [part.decode("utf-8") for part in raw.split(b"\0") if part]
        expected_args = [
            "-f", "-N", "-L", "8025:localhost:25",
            "mailadmin@mail.local", "-i", "/home/user/.ssh/mail_rsa"
        ]
        assert actual_args == expected_args, \
            f"start_tunnel invoked ssh with {actual_args!r}, expected {expected_args!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
