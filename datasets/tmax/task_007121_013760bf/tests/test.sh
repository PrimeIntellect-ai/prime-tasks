#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
import time
from collections import defaultdict
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime


def test_script_exists_and_executable():
    script_path = "/home/user/process_loc.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_sampled_loc_tsv_content():
    input_path = "/home/user/loc_events.tsv"
    output_path = "/home/user/sampled_loc.tsv"

    assert os.path.isfile(input_path), f"Input file {input_path} missing."
    assert os.path.isfile(output_path), f"Output file {output_path} missing."

    with open(input_path, "r", encoding="utf-8") as f:
        input_lines = f.read().splitlines()

    # Compute expected output
    parsed_records = []
    for line in input_lines:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) >= 4:
            parsed_records.append(parts)

    # Sort chronologically
    parsed_records.sort(key=lambda x: x[0])

    expected_records = []
    lang_counts = defaultdict(int)

    for parts in parsed_records:
        ts, email, lang, text = parts[0], parts[1], parts[2], parts[3:]

        # Mask email
        if "@" in email:
            user, domain = email.split("@", 1)
            masked_user = user[0] + "*" if len(user) > 0 else "*"
            masked_email = f"{masked_user}@{domain}"
        else:
            masked_email = email

        if lang_counts[lang] < 2:
            expected_records.append("\t".join([ts, masked_email, lang] + text))
            lang_counts[lang] += 1

    with open(output_path, "r", encoding="utf-8") as f:
        output_lines = [line for line in f.read().splitlines() if line.strip()]

    # Check that output matches expected
    assert len(output_lines) == len(expected_records), f"Expected {len(expected_records)} rows in output, but got {len(output_lines)}."

    for i, (expected, actual) in enumerate(zip(expected_records, output_lines)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def test_pipeline_log_content():
    log_path = "/home/user/pipeline.log"
    assert os.path.isfile(log_path), f"Log file {log_path} missing."

    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {log_path}, got {len(lines)}."

    assert lines[0].startswith("[START]"), "First line must start with [START]."
    assert lines[3].startswith("[END]"), "Fourth line must start with [END]."

    # The input has 10 lines, output has 9 lines
    assert "[PROCESSED] 10" in lines[1] or "[PROCESSED] 10" in lines[2], "Log must contain '[PROCESSED] 10'."
    assert "[OUTPUT] 9" in lines[1] or "[OUTPUT] 9" in lines[2], "Log must contain '[OUTPUT] 9'."

    # Ensure order of PROCESSED and OUTPUT
    assert lines[1].startswith("[PROCESSED]"), "Second line must start with [PROCESSED]."
    assert lines[2].startswith("[OUTPUT]"), "Third line must start with [OUTPUT]."


def _expected(lines):
    records = [line.split("\t") for line in lines if line.strip()]
    records.sort(key=lambda p: p[0])
    counts = defaultdict(int)
    result = []
    for parts in records:
        ts, email, lang = parts[:3]
        text = parts[3:]
        if counts[lang] >= 2:
            continue
        user, domain = email.split("@", 1)
        masked = (user[0] if user else "") + "*@" + domain
        result.append("\t".join([ts, masked, lang] + text))
        counts[lang] += 1
    return result


def _utc_timestamp(value):
    value = value.strip()
    parsed = None
    try:
        parsed = datetime.fromisoformat(value[:-1] + "+00:00" if value.endswith("Z") else value)
    except ValueError:
        pass
    if parsed is None:
        try:
            parsed = parsedate_to_datetime(value)
        except (TypeError, ValueError):
            pass
    if parsed is None:
        try:
            parsed = datetime.strptime(value, "%a %b %d %H:%M:%S UTC %Y").replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    assert parsed is not None, f"Unrecognized timestamp: {value!r}"
    assert parsed.tzinfo is not None, f"Timestamp is not explicitly UTC: {value!r}"
    assert parsed.utcoffset().total_seconds() == 0, f"Timestamp is not UTC: {value!r}"
    return parsed.timestamp()


def _run_and_check(input_lines, wrapper_dir, invocation_log):
    input_path = "/home/user/loc_events.tsv"
    output_path = "/home/user/sampled_loc.tsv"
    log_path = "/home/user/pipeline.log"

    with open(input_path, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(input_lines) + "\n")
    for path in (output_path, log_path):
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "/usr/bin:/bin")
    env["FORBIDDEN_INVOCATION_LOG"] = invocation_log
    before = time.time()
    result = subprocess.run(
        ["/home/user/process_loc.sh"],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    after = time.time()
    assert result.returncode == 0, f"Script failed on modified input:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert os.path.isfile(output_path), "Script did not create sampled_loc.tsv."
    assert os.path.isfile(log_path), "Script did not create pipeline.log."

    with open(output_path, "r", encoding="utf-8") as f:
        actual = f.read().splitlines()
    expected = _expected(input_lines)
    assert actual == expected, f"Modified-input output mismatch.\nExpected: {expected!r}\nActual: {actual!r}"

    with open(log_path, "r", encoding="utf-8") as f:
        log_lines = f.read().splitlines()
    assert log_lines == [
        log_lines[0] if len(log_lines) > 0 else "",
        f"[PROCESSED] {len(input_lines)}",
        f"[OUTPUT] {len(expected)}",
        log_lines[3] if len(log_lines) > 3 else "",
    ], f"Log must contain exactly four correctly ordered lines; got {log_lines!r}"
    assert len(log_lines) == 4
    start_match = re.fullmatch(r"\[START\] (.+)", log_lines[0])
    end_match = re.fullmatch(r"\[END\] (.+)", log_lines[3])
    assert start_match and end_match, f"Invalid START/END log lines: {log_lines!r}"
    start = _utc_timestamp(start_match.group(1))
    end = _utc_timestamp(end_match.group(1))
    assert before - 5 <= start <= after + 5, "START timestamp was not generated during this run."
    assert before - 5 <= end <= after + 5, "END timestamp was not generated during this run."
    assert start <= end, "END timestamp precedes START timestamp."


def test_script_executes_pipeline_on_modified_inputs_without_forbidden_languages():
    script_path = "/home/user/process_loc.sh"
    with open(script_path, "r", encoding="utf-8") as f:
        source = f.read()

    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.fullmatch(r"#!\s*(?:/bin/bash|/usr/bin/bash|/usr/bin/env\s+bash)\s*", first_line), "process_loc.sh must be a Bash script."
    syntax = subprocess.run(["/bin/bash", "-n", script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert syntax.returncode == 0, f"Invalid Bash syntax: {syntax.stderr}"

    command_source = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    forbidden = re.compile(r"(^|[\s/;&|`(])(python(?:[0-9.]*)?|perl|ruby)(?=$|[\s;&|`)<>])", re.MULTILINE | re.IGNORECASE)
    assert not forbidden.search(command_source), "Python, Perl, and Ruby are prohibited in process_loc.sh."

    paths = ["/home/user/loc_events.tsv", "/home/user/sampled_loc.tsv", "/home/user/pipeline.log"]
    saved = {path: (open(path, "rb").read() if os.path.exists(path) else None) for path in paths}
    try:
        with tempfile.TemporaryDirectory() as wrapper_dir:
            invocation_log = os.path.join(wrapper_dir, "forbidden.log")
            wrapper = "#!/bin/sh\necho \"$0 $*\" >> \"$FORBIDDEN_INVOCATION_LOG\"\nexit 97\n"
            for name in ("python", "python2", "python3", "perl", "ruby"):
                path = os.path.join(wrapper_dir, name)
                with open(path, "w", encoding="utf-8") as f:
                    f.write(wrapper)
                os.chmod(path, 0o755)

            case_one = [
                "2025-03-05T09:00:00Z\tzeta.long@one.example\tZZ\tآخر حدث",
                "2025-03-01T12:00:00Z\ta@tiny.test\tAA\t一番目",
                "2025-03-04T09:00:00Z\tbob@two.example\tZZ\tsecond",
                "2025-03-02T08:00:00Z\tcharlie.delta@three.example\tBB\tПривет",
                "2025-03-03T08:00:00Z\tdora@four.example\tBB\tmañana",
                "2025-03-01T13:00:00Z\techo@five.example\tZZ\tfirst zz",
            ]
            case_two = [
                "2024-12-31T23:59:59Z\tlong.username@domain.invalid\tNEW\tlate",
                "2024-01-01T00:00:02Z\tx@y.invalid\tNEW\tmiddle",
                "2024-01-01T00:00:01Z\tfirst.person@z.invalid\tNEW\tearly",
                "2024-06-01T10:10:10Z\tsolo@only.invalid\tONE\t独立",
            ]
            _run_and_check(case_one, wrapper_dir, invocation_log)
            _run_and_check(case_two, wrapper_dir, invocation_log)
            assert not os.path.exists(invocation_log) or os.path.getsize(invocation_log) == 0, "Script invoked Python, Perl, or Ruby."
    finally:
        for path, content in saved.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
