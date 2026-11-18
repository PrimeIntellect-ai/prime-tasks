#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import re
import secrets
import subprocess
import tempfile
import zipfile
import zlib

import pytest

SCRIPT_PATH = "/home/user/ci_guard.sh"
CLEAN_CORPUS = "/app/corpus/clean"
EVIL_CORPUS = "/app/corpus/evil"


def run_guard(*args, timeout=120):
    return subprocess.run(
        [SCRIPT_PATH, *map(str, args)],
        cwd="/",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def write_checked(path, body, valid=True):
    data = body.encode("utf-8")
    crc = zlib.crc32(data) & 0xFFFFFFFF
    if not valid:
        crc ^= 1
    with open(path, "wb") as f:
        f.write(f"# CHECKSUM: {crc:08x}\n".encode("ascii"))
        f.write(data)


def make_project(root, files, requirements=""):
    os.makedirs(root)
    for name, body in files.items():
        path = os.path.join(root, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_checked(path, body)
    with open(os.path.join(root, "requirements.txt"), "w", encoding="utf-8") as f:
        f.write(requirements)


def test_script_exists_and_is_guard_artifact():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"The script {SCRIPT_PATH} is not executable."
    data = open(SCRIPT_PATH, "rb").read()
    first = data.splitlines()[0] if data.splitlines() else b""
    assert first.startswith(b"#!") and (b"sh" in first or b"bash" in first), "ci_guard.sh is not a shell script"

    text = data.decode("utf-8", "replace")
    assert "ci_telemetry.mp4" in text, "the guard does not use the supplied telemetry video"
    extracts_video = ("ffmpeg" in text and ("zbar" in text or "qr" in text.lower()))
    uses_decoded_values = ("EDB88320" in text.upper() and "STRICT" in text.upper())
    assert extracts_video or uses_decoded_values, "the decoded telemetry configuration is neither extracted nor used"
    assert re.search(r"(?:python(?:3)?[^\n]*-m\s+venv|virtualenv|venv\.EnvBuilder)", text), "the guard does not create a virtual environment"


def test_argument_count_behavior():
    assert run_guard().returncode == 1, "zero arguments must exit 1"
    with tempfile.TemporaryDirectory(prefix="guard-args-") as d:
        assert run_guard(d, d).returncode == 1, "two arguments must exit 1"
    missing = os.path.join("/tmp", "guard-missing-" + secrets.token_hex(8))
    assert run_guard(missing).returncode == 1, "a nonexistent project directory must exit 1"


def test_adversarial_corpus():
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus missing at {CLEAN_CORPUS}"
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus missing at {EVIL_CORPUS}"

    clean_projects = sorted(os.path.join(CLEAN_CORPUS, d) for d in os.listdir(CLEAN_CORPUS)
                            if os.path.isdir(os.path.join(CLEAN_CORPUS, d)))
    evil_projects = sorted(os.path.join(EVIL_CORPUS, d) for d in os.listdir(EVIL_CORPUS)
                           if os.path.isdir(os.path.join(EVIL_CORPUS, d)))
    assert clean_projects, "No clean projects found."
    assert evil_projects, "No evil projects found."

    clean_failures = [os.path.basename(p) for p in clean_projects if run_guard(p).returncode != 0]
    evil_failures = [os.path.basename(p) for p in evil_projects if run_guard(p).returncode != 1]
    errors = []
    if evil_failures:
        errors.append(f"{len(evil_failures)} of {len(evil_projects)} evil projects did not exit 1: {', '.join(evil_failures)}")
    if clean_failures:
        errors.append(f"{len(clean_failures)} of {len(clean_projects)} clean projects were rejected: {', '.join(clean_failures)}")
    if errors:
        pytest.fail(" | ".join(errors))


def test_randomized_crc_and_import_cases():
    token = "m" + secrets.token_hex(6)
    with tempfile.TemporaryDirectory(prefix="unrelated-projects-") as base:
        clean = os.path.join(base, secrets.token_hex(8))
        make_project(clean, {
            f"{token}a.py": "VALUE = 7\n",
            f"{token}b.py": f"import {token}a\nassert {token}a.VALUE == 7\n",
        })
        assert run_guard(clean).returncode == 0, "a randomized valid project was rejected"

        bad_crc = os.path.join(base, secrets.token_hex(8))
        make_project(bad_crc, {f"{token}c.py": "VALUE = 9\n"})
        path = os.path.join(bad_crc, f"{token}c.py")
        with open(path, "ab") as f:
            f.write(b"# mutation\n")
        assert run_guard(bad_crc).returncode == 1, "a dynamically corrupted CRC was accepted"

        missing_header = os.path.join(base, secrets.token_hex(8))
        make_project(missing_header, {f"{token}d.py": "VALUE = 1\n"})
        path = os.path.join(missing_header, f"{token}d.py")
        with open(path, "wb") as f:
            f.write(b"VALUE = 1\n")
        assert run_guard(missing_header).returncode == 1, "a file without the exact checksum header was accepted"

        import_error = os.path.join(base, secrets.token_hex(8))
        make_project(import_error, {f"{token}e.py": "raise ImportError('generated failure')\n"})
        assert run_guard(import_error).returncode == 1, "an import-time ImportError was accepted"

        circular_error = os.path.join(base, secrets.token_hex(8))
        make_project(circular_error, {
            f"{token}x.py": f"from {token}y import VALUE_Y\nVALUE_X = 1\n",
            f"{token}y.py": f"from {token}x import VALUE_X\nVALUE_Y = 2\n",
        })
        assert run_guard(circular_error).returncode == 1, "a circular dependency that raises ImportError was accepted"


def test_requirements_are_installed_without_polluting_system_python():
    token = "guarddep" + secrets.token_hex(6)
    assert importlib.util.find_spec(token) is None

    with tempfile.TemporaryDirectory(prefix="guard-dependency-") as base:
        wheel = os.path.join(base, f"{token}-1.0-py3-none-any.whl")
        dist_info = f"{token}-1.0.dist-info"
        with zipfile.ZipFile(wheel, "w") as z:
            z.writestr(f"{token}.py", "VALUE = 314159\n")
            z.writestr(f"{dist_info}/METADATA", f"Metadata-Version: 2.1\nName: {token}\nVersion: 1.0\n")
            z.writestr(f"{dist_info}/WHEEL", "Wheel-Version: 1.0\nGenerator: verifier\nRoot-Is-Purelib: true\nTag: py3-none-any\n")
            z.writestr(f"{dist_info}/RECORD", "")

        project = os.path.join(base, secrets.token_hex(8))
        make_project(project, {
            "consumer.py": f"import {token}\nassert {token}.VALUE == 314159\n",
        }, requirements=wheel + "\n")
        assert run_guard(project).returncode == 0, "a project requiring an installable local dependency was rejected"

    probe = subprocess.run(
        ["python3", "-c", f"import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('{token}') is None else 1)"],
        cwd="/", env={"PATH": os.environ.get("PATH", "")}, timeout=20,
    )
    assert probe.returncode == 0, "requirements were installed into the system interpreter instead of an isolated environment"


def test_requirement_install_failure_is_evil():
    with tempfile.TemporaryDirectory(prefix="guard-bad-requirement-") as base:
        project = os.path.join(base, secrets.token_hex(8))
        impossible = os.path.join(base, "does-not-exist-" + secrets.token_hex(8) + ".whl")
        make_project(project, {"valid.py": "VALUE = 1\n"}, requirements=impossible + "\n")
        assert run_guard(project).returncode == 1, "a requirements installation failure was accepted"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
