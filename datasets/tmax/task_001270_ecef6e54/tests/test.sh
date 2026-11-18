#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import re
import secrets
import stat
import string
import subprocess
import tempfile
import uuid

import pytest

CLEAN_CORPUS_DIR = "/home/user/corpus/clean"
EVIL_CORPUS_DIR = "/home/user/corpus/evil"
PIPELINE_SCRIPT = "/home/user/pipeline.sh"
CRON_RUNNER_SCRIPT = "/home/user/cron_runner.sh"
MASKER_DIR = "/app/log-masker-1.0.0"
MASKER_BIN = os.path.join(MASKER_DIR, "masker")
INCOMING_DIR = "/home/user/incoming"
OUTGOING_DIR = "/home/user/outgoing"


def run(command, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 20)
    return subprocess.run(command, **kwargs)


def expected_masked(content):
    content = re.sub(r"api_key=[a-zA-Z0-9]{32}", "api_key=[REDACTED]", content)
    return re.sub(r"ssn=[0-9]{9}", "ssn=[REDACTED]", content)


def random_alnum(length):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


@contextlib.contextmanager
def executable_wrapper(path, body):
    real_path = path + ".verifier-real-" + uuid.uuid4().hex
    os.replace(path, real_path)
    try:
        with open(path, "w") as wrapper:
            wrapper.write("#!/bin/sh\n")
            wrapper.write(body.format(real=real_path))
        os.chmod(path, 0o755)
        yield real_path
    finally:
        if os.path.lexists(path):
            os.unlink(path)
        if os.path.exists(real_path):
            os.replace(real_path, path)


def test_masker_compiled_from_fixed_makefile_and_works():
    makefile = os.path.join(MASKER_DIR, "Makefile")
    assert os.path.isfile(makefile), f"{makefile} does not exist."

    # The fixed build must be able to recreate the artifact, rather than relying
    # on an executable placed in the directory by some unrelated mechanism.
    if os.path.lexists(MASKER_BIN):
        os.unlink(MASKER_BIN)
    result = run(["make", "-B", "masker"], cwd=MASKER_DIR)
    assert result.returncode == 0, f"The vendored Makefile cannot build masker:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(MASKER_BIN), f"{MASKER_BIN} does not exist. Did you compile the vendored package?"
    assert os.access(MASKER_BIN, os.X_OK), f"{MASKER_BIN} is not executable."
    with open(MASKER_BIN, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "masker is not a compiled executable."

    api_key = random_alnum(32)
    ssn = "".join(secrets.choice(string.digits) for _ in range(9))
    content = (
        f"timestamp={secrets.randbelow(9000000000) + 1000000000} metric=request api_key={api_key} value=7\n"
        f"timestamp={secrets.randbelow(9000000000) + 1000000000} metric=signup ssn={ssn} value=1\n"
        f"timestamp=42 metric=clean api_key={random_alnum(31)} ssn=12345678 value=3\n"
    )
    with tempfile.NamedTemporaryFile("w", delete=False) as source:
        source.write(content)
        source_path = source.name
    try:
        result = run([MASKER_BIN, source_path])
        assert result.returncode == 0, result.stderr
        assert result.stdout == expected_masked(content)
    finally:
        os.unlink(source_path)


def test_pipeline_script_exists_and_executable():
    assert os.path.isfile(PIPELINE_SCRIPT), f"{PIPELINE_SCRIPT} does not exist."
    assert os.access(PIPELINE_SCRIPT, os.X_OK), f"{PIPELINE_SCRIPT} is not executable."


def test_adversarial_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    evil_files = [f for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_modified = []
    evil_bypassed = []

    with tempfile.TemporaryDirectory() as tmpdir:
        for basename in clean_files:
            input_path = os.path.join(CLEAN_CORPUS_DIR, basename)
            output_path = os.path.join(tmpdir, f"clean_{basename}")
            result = run([PIPELINE_SCRIPT, input_path, output_path])
            if result.returncode != 0 or not os.path.isfile(output_path):
                clean_modified.append(basename)
                continue
            with open(input_path) as source, open(output_path) as output:
                if source.read() != output.read():
                    clean_modified.append(basename)

        for basename in evil_files:
            input_path = os.path.join(EVIL_CORPUS_DIR, basename)
            output_path = os.path.join(tmpdir, f"evil_{basename}")
            result = run([PIPELINE_SCRIPT, input_path, output_path])
            if result.returncode != 0 or not os.path.isfile(output_path):
                evil_bypassed.append(basename)
                continue
            with open(output_path) as output:
                processed_content = output.read()
            if re.search(r"api_key=[a-zA-Z0-9]{32}", processed_content) or re.search(r"ssn=[0-9]{9}", processed_content):
                evil_bypassed.append(basename)
            elif "api_key=[REDACTED]" not in processed_content and "ssn=[REDACTED]" not in processed_content:
                evil_bypassed.append(basename)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_pipeline_general_behavior_and_masker_invocation():
    api_key = random_alnum(32)
    ssn = "".join(secrets.choice(string.digits) for _ in range(9))
    nonce = uuid.uuid4().hex
    content = (
        f"timestamp=2000000001 metric={nonce} host=random-host value=19.75\n"
        f"timestamp=2000000002 metric=request api_key={api_key} middle=ok ssn={ssn} value=4\n"
        f"timestamp=2000000003 metric=tail ssn={ssn} api_key={api_key}\n"
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, uuid.uuid4().hex + ".log")
        output_path = os.path.join(tmpdir, uuid.uuid4().hex + ".sanitized")
        call_log = os.path.join("/tmp", "masker-calls-" + uuid.uuid4().hex)
        open(call_log, "w").close()
        os.chmod(call_log, 0o666)
        with open(input_path, "w") as source:
            source.write(content)

        wrapper_body = f"printf '%s\\n' called >> '{call_log}'\nexec '{{real}}' \"$@\"\n"
        try:
            with executable_wrapper(MASKER_BIN, wrapper_body):
                result = run([PIPELINE_SCRIPT, input_path, output_path])
            assert result.returncode == 0, result.stderr
            assert os.path.isfile(output_path), "pipeline did not create its requested output file"
            with open(output_path) as output:
                assert output.read() == expected_masked(content)
            with open(call_log) as calls:
                assert calls.read().strip(), "pipeline did not invoke the vendored masker executable"
        finally:
            if os.path.exists(call_log):
                os.unlink(call_log)

        assert run([PIPELINE_SCRIPT]).returncode != 0, "pipeline must reject calls with fewer than two arguments"
        extra_output = os.path.join(tmpdir, "extra-output")
        assert run([PIPELINE_SCRIPT, input_path, extra_output, "extra"]).returncode != 0, "pipeline must reject calls with more than two arguments"


def test_cron_job_installed_for_user():
    result = run(["crontab", "-u", "user", "-l"])
    assert result.returncode == 0, "No crontab is installed for the user account."
    expected_cron = f"*/5 * * * * {CRON_RUNNER_SCRIPT}"
    found = False
    for line in result.stdout.splitlines():
        line = line.strip()
        if line == expected_cron or (line.startswith("*/5 * * * *") and CRON_RUNNER_SCRIPT in line):
            found = True
            break
    assert found, f"Cron job not correctly installed for user. Expected to find '{expected_cron}'."


def test_cron_runner_script_exists_and_executable():
    assert os.path.isfile(CRON_RUNNER_SCRIPT), f"{CRON_RUNNER_SCRIPT} does not exist."
    assert os.access(CRON_RUNNER_SCRIPT, os.X_OK), f"{CRON_RUNNER_SCRIPT} is not executable."


def test_cron_runner_processes_dynamic_files_via_pipeline():
    token = uuid.uuid4().hex
    names = [f"verification-{token}-a.log", f"verification-{token}-b.log"]
    contents = [
        f"timestamp=3000000001 metric=clean-{token} value=8\n",
        f"timestamp=3000000002 metric=secret api_key={random_alnum(32)} ssn={''.join(secrets.choice(string.digits) for _ in range(9))}\n",
    ]
    unrelated_name = f"verification-{token}.txt"
    unrelated_path = os.path.join(INCOMING_DIR, unrelated_name)
    call_log = os.path.join("/tmp", "pipeline-calls-" + token)
    open(call_log, "w").close()
    os.chmod(call_log, 0o666)

    for name, content in zip(names, contents):
        with open(os.path.join(INCOMING_DIR, name), "w") as source:
            source.write(content)
    with open(unrelated_path, "w") as source:
        source.write("do not process this file\n")

    wrapper_body = f"printf '%s\\t%s\\n' \"$1\" \"$2\" >> '{call_log}'\nexec '{{real}}' \"$@\"\n"
    try:
        with executable_wrapper(PIPELINE_SCRIPT, wrapper_body):
            result = run(["runuser", "-u", "user", "--", CRON_RUNNER_SCRIPT])
        assert result.returncode == 0, f"cron runner failed:\n{result.stdout}\n{result.stderr}"

        with open(call_log) as calls_file:
            calls = calls_file.read()
        for name, content in zip(names, contents):
            incoming = os.path.join(INCOMING_DIR, name)
            outgoing = os.path.join(OUTGOING_DIR, name)
            assert not os.path.exists(incoming), f"cron runner did not delete {incoming}"
            assert os.path.isfile(outgoing), f"cron runner did not create {outgoing}"
            with open(outgoing) as output:
                assert output.read() == expected_masked(content)
            assert f"{incoming}\t{outgoing}" in calls, f"cron runner did not process {name} through pipeline.sh"
        assert os.path.isfile(unrelated_path), "cron runner must only consume .log files"
    finally:
        for name in names:
            for directory in (INCOMING_DIR, OUTGOING_DIR):
                path = os.path.join(directory, name)
                if os.path.exists(path):
                    os.unlink(path)
        if os.path.exists(unrelated_path):
            os.unlink(unrelated_path)
        if os.path.exists(call_log):
            os.unlink(call_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
