#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import configparser
import glob
import importlib.util
import os
import random
import re
import shlex
import signal
import string
import subprocess
import tarfile
import tempfile
import time

import pytest

ARCHIVER = "/home/user/archiver.py"


def load_archiver():
    assert os.path.isfile(ARCHIVER), "archiver.py is missing"
    spec = importlib.util.spec_from_file_location("submitted_archiver", ARCHIVER)
    assert spec and spec.loader, "Could not load archiver.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    func = getattr(module, "sanitize_and_archive", None)
    assert callable(func), "sanitize_and_archive is missing or not callable"
    return func


def read_archive(path):
    assert os.path.isfile(path), "archive was not created"
    with tarfile.open(path, "r:gz") as archive:
        members = [member for member in archive.getmembers() if member.isfile()]
        assert members, "archive contains no text file"
        extracted = archive.extractfile(members[0])
        assert extracted is not None, "could not read archived file"
        return extracted.read().decode("utf-8", errors="strict")


def random_token(length=12):
    alphabet = string.ascii_letters + string.digits
    return "".join(random.SystemRandom().choice(alphabet) for _ in range(length))


def test_archiver_evil_corpus():
    sanitize_and_archive = load_archiver()
    evil_dir = "/home/user/corpora/evil"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    failures = []
    for filename in os.listdir(evil_dir):
        input_path = os.path.join(evil_dir, filename)
        raw = open(input_path, "rb").read()
        with tempfile.TemporaryDirectory() as tmpdir:
            output_archive = os.path.join(tmpdir, filename + ".tar.gz")
            try:
                result = sanitize_and_archive(input_path, output_archive)
                if raw.startswith(b"\x89PNG"):
                    if result is not False:
                        failures.append(f"{filename} (binary input was not rejected)")
                    if os.path.exists(output_archive):
                        failures.append(f"{filename} (binary input produced an archive)")
                    continue

                if result is not True:
                    failures.append(f"{filename} (text containing secrets was rejected)")
                    continue
                content = read_archive(output_archive)
                if re.search(r"\b(?:\d[ -]*?){15}\d\b", content):
                    failures.append(f"{filename} (unsanitized CC found)")
                if "-----BEGIN RSA PRIVATE KEY-----" in content or "-----END RSA PRIVATE KEY-----" in content:
                    failures.append(f"{filename} (unsanitized RSA key found)")
                if b"1234-5678-9012-3456" in raw and "[REDACTED_CC]" not in content:
                    failures.append(f"{filename} (CC replacement marker missing)")
                if b"BEGIN RSA PRIVATE KEY" in raw and "[REDACTED_KEY]" not in content:
                    failures.append(f"{filename} (key replacement marker missing)")
            except Exception as exc:
                failures.append(f"{filename} (crashed: {exc})")

    if failures:
        pytest.fail("; ".join(failures))


def test_archiver_clean_corpus():
    sanitize_and_archive = load_archiver()
    clean_dir = "/home/user/corpora/clean"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    failures = []
    for filename in os.listdir(clean_dir):
        input_path = os.path.join(clean_dir, filename)
        with open(input_path, "r", encoding="utf-8") as source:
            original = source.read()
        with tempfile.TemporaryDirectory() as tmpdir:
            output_archive = os.path.join(tmpdir, filename + ".tar.gz")
            try:
                result = sanitize_and_archive(input_path, output_archive)
                if result is not True:
                    failures.append(f"{filename} (returned False or rejected)")
                elif read_archive(output_archive) != original:
                    failures.append(f"{filename} (content modified)")
            except Exception as exc:
                failures.append(f"{filename} (crashed: {exc})")

    if failures:
        pytest.fail("; ".join(failures))


def test_randomized_sanitization_and_binary_rejection():
    sanitize_and_archive = load_archiver()
    rng = random.SystemRandom()
    digits = "".join(str(rng.randrange(10)) for _ in range(16))
    dashed = "-".join(digits[i:i + 4] for i in range(0, 16, 4))
    compact = "".join(str(rng.randrange(10)) for _ in range(16))
    key_body = random_token(48)
    original = (
        f"session={random_token()}\n"
        f"first card {dashed} accepted\n"
        f"second card {compact} accepted\n"
        "-----BEGIN RSA PRIVATE KEY-----\n"
        f"{key_body}\n"
        "more-key-material\n"
        "-----END RSA PRIVATE KEY-----\n"
        f"finished={random_token()}\n"
    )
    expected = (
        original.replace(dashed, "[REDACTED_CC]")
        .replace(compact, "[REDACTED_CC]")
    )
    expected = re.sub(
        r"-----BEGIN RSA PRIVATE KEY-----.*?-----END RSA PRIVATE KEY-----",
        "[REDACTED_KEY]",
        expected,
        flags=re.DOTALL,
    )

    with tempfile.TemporaryDirectory() as tmpdir:
        source = os.path.join(tmpdir, random_token() + ".log")
        output = os.path.join(tmpdir, random_token() + ".tar.gz")
        with open(source, "w", encoding="utf-8") as handle:
            handle.write(original)
        result = sanitize_and_archive(source, output)
        assert result is True, "text containing secrets must be sanitized, not rejected"
        assert read_archive(output) == expected

        binary_source = os.path.join(tmpdir, random_token() + ".bin")
        binary_output = os.path.join(tmpdir, random_token() + ".tar.gz")
        with open(binary_source, "wb") as handle:
            handle.write(b"\x89PNG\r\n\x1a\n" + os.urandom(24))
        assert sanitize_and_archive(binary_source, binary_output) is False
        assert not os.path.exists(binary_output), "corrupt binary input must be dropped"


def test_cli_entrypoint():
    content = f"alpha={random_token()}\ncard=1111-2222-3333-4444\nomega={random_token()}\n"
    expected = content.replace("1111-2222-3333-4444", "[REDACTED_CC]")
    with tempfile.TemporaryDirectory() as tmpdir:
        source = os.path.join(tmpdir, random_token() + ".log")
        output = os.path.join(tmpdir, random_token() + ".tar.gz")
        with open(source, "w", encoding="utf-8") as handle:
            handle.write(content)
        completed = subprocess.run(
            ["python3", ARCHIVER, "--input", source, "--output", output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert completed.returncode == 0, completed.stderr
        assert read_archive(output) == expected


def test_config_ini():
    config_path = "/home/user/app/config.ini"
    assert os.path.isfile(config_path), "config.ini missing"
    with open(config_path, "r", encoding="utf-8") as handle:
        content = handle.read()
    assert "python /home/user/archiver.py" in content, "config.ini does not point to python /home/user/archiver.py"


def test_start_pipeline_script_exists():
    script_path = "/home/user/start_pipeline.sh"
    assert os.path.isfile(script_path), "start_pipeline.sh is missing"
    assert os.access(script_path, os.X_OK) or os.stat(script_path).st_mode & 0o111, "start_pipeline.sh is not executable"


def write_executable(path, content):
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)
    os.chmod(path, 0o755)


def test_pipeline_watches_archives_and_records_redis():
    script_path = "/home/user/start_pipeline.sh"
    assert os.path.isfile(script_path), "start_pipeline.sh is missing"
    assert os.access(script_path, os.X_OK) or os.stat(script_path).st_mode & 0o111, "start_pipeline.sh is not executable"

    raw_dir = "/home/user/app/logs/raw"
    archive_dir = "/home/user/app/logs/archives"
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(archive_dir, exist_ok=True)

    token = random_token(18)
    source = os.path.join(raw_dir, f"pipeline-{token}.log")
    original = f"begin {token}\npayment 9876-5432-1098-7654\nend {token}\n"
    expected = original.replace("9876-5432-1098-7654", "[REDACTED_CC]")
    with open(source, "w", encoding="utf-8") as handle:
        handle.write(original)

    with tempfile.TemporaryDirectory() as tmpdir:
        calls = os.path.join(tmpdir, "calls")
        os.mkdir(calls)
        mockbin = os.path.join(tmpdir, "bin")
        os.mkdir(mockbin)

        write_executable(os.path.join(mockbin, "docker-compose"), """#!/bin/bash
printf 'docker-compose %s\\n' "$*" >> "$CALLS/docker"
exit 0
""")
        write_executable(os.path.join(mockbin, "docker"), """#!/bin/bash
printf 'docker %s\\n' "$*" >> "$CALLS/docker"
exit 0
""")
        write_executable(os.path.join(mockbin, "sleep"), """#!/bin/bash
printf '%s\\n' "$*" >> "$CALLS/sleep"
exit 0
""")
        write_executable(os.path.join(mockbin, "redis-cli"), """#!/bin/bash
printf '%s\\n' "$*" >> "$CALLS/redis"
exit 0
""")
        write_executable(os.path.join(mockbin, "inotifywait"), """#!/bin/bash
printf '%s\\n' "$*" >> "$CALLS/inotify"
fmt=''
want_fmt=0
for arg in "$@"; do
    if [ "$want_fmt" = 1 ]; then fmt="$arg"; want_fmt=0; continue; fi
    case "$arg" in
        --format) want_fmt=1 ;;
        --format=*) fmt="${arg#--format=}" ;;
    esac
done
case "$fmt" in
    *%w*%f*) printf '%s\\n' "$EVENT_PATH" ;;
    *%f*) basename "$EVENT_PATH" ;;
    *) printf '%s/ CLOSE_WRITE,CLOSE %s\\n' "$(dirname "$EVENT_PATH")" "$(basename "$EVENT_PATH")" ;;
esac
/bin/sleep 30
""")

        env = os.environ.copy()
        env["PATH"] = mockbin + os.pathsep + env.get("PATH", "")
        env["CALLS"] = calls
        env["EVENT_PATH"] = source
        started = time.time()
        process = subprocess.Popen(
            ["/bin/bash", script_path],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )

        matching_archive = None
        try:
            deadline = time.time() + 12
            while time.time() < deadline:
                candidates = []
                for path in glob.glob(os.path.join(archive_dir, "**", "*.tar.gz"), recursive=True):
                    try:
                        if os.path.getmtime(path) >= started - 0.5 and token in read_archive(path):
                            candidates.append(path)
                    except Exception:
                        pass
                redis_log = os.path.join(calls, "redis")
                if candidates and os.path.isfile(redis_log):
                    matching_archive = candidates[0]
                    break
                if process.poll() is not None:
                    break
                time.sleep(0.1)
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=2)

        assert matching_archive is not None, "pipeline did not archive the close-written log"
        assert read_archive(matching_archive) == expected

        docker_log = open(os.path.join(calls, "docker"), encoding="utf-8").read()
        assert re.search(r"(?:docker-compose|docker compose).*\bup\b.*(?:-d|--detach)", docker_log), "pipeline did not start docker-compose in the background"

        sleep_log = open(os.path.join(calls, "sleep"), encoding="utf-8").read().splitlines()
        assert any(value.strip() in ("5", "5s") for value in sleep_log), "pipeline did not wait 5 seconds"

        inotify_log = open(os.path.join(calls, "inotify"), encoding="utf-8").read()
        assert raw_dir in inotify_log, "inotifywait is not watching the raw log directory"
        assert "close_write" in inotify_log.lower(), "inotifywait is not watching close_write events"
        assert re.search(r"(^|\s)(-m|--monitor)(\s|$)", inotify_log), "inotifywait is not running continuously"

        redis_lines = open(os.path.join(calls, "redis"), encoding="utf-8").read().splitlines()
        archive_name = os.path.basename(matching_archive)
        recorded = False
        for line in redis_lines:
            words = shlex.split(line)
            for index in range(max(0, len(words) - 2)):
                if words[index].upper() == "LPUSH" and words[index + 1] == "archived_logs" and words[index + 2] == archive_name:
                    recorded = True
        assert recorded, "successful archive name was not LPUSHed to archived_logs"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
