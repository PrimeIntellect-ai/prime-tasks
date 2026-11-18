#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import uuid
import resource

EXTRACT = "/home/user/extract.py"
PIPELINE = "/home/user/pipeline.sh"
MESSY = "/home/user/messy_data.log"
EXTRACTED = "/home/user/extracted.csv"
CLEAN = "/home/user/clean_data.csv"

TIMESTAMP_RE = re.compile(r"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]")
EMAIL_RE = re.compile(r"(?<![A-Za-z0-9._%+\-])[A-Za-z0-9._%+\-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?![A-Za-z0-9._%+\-])")


def read_nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def expected_extract(lines):
    result = []
    for line in lines:
        timestamps = TIMESTAMP_RE.findall(line)
        emails = EMAIL_RE.findall(line)
        if len(timestamps) == 1 and len(emails) == 1:
            result.append(f"{timestamps[0]},{emails[0]}")
    return result


def test_extract_script_exists():
    assert os.path.exists(EXTRACT), f"Expected script {EXTRACT} does not exist."
    assert os.path.isfile(EXTRACT), f"{EXTRACT} is not a file."


def test_pipeline_script_exists_and_executable():
    assert os.path.exists(PIPELINE), f"Expected script {PIPELINE} does not exist."
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is not a file."
    st = os.stat(PIPELINE)
    assert st.st_mode & stat.S_IXUSR, f"{PIPELINE} is not executable by the owner."


def test_clean_data_csv_content():
    assert os.path.exists(CLEAN), f"Expected output file {CLEAN} does not exist."
    assert os.path.isfile(CLEAN), f"{CLEAN} is not a file."

    expected_lines = [
        "2022-12-31 23:59:59,new_year@party.org",
        "2023-10-14 08:30:00,admin@server.local",
        "2023-10-15 09:15:22,root@localhost",
        "2023-10-16 11:11:11,user.test@enterprise.com"
    ]
    actual_lines = read_nonempty_lines(CLEAN)
    assert actual_lines == expected_lines, (
        f"The content of {CLEAN} does not match the expected final output.\n"
        f"Expected: {expected_lines}\nActual: {actual_lines}"
    )


def test_extractor_and_pipeline_on_generated_inputs():
    token = uuid.uuid4().hex[:12]
    original_extract = open(EXTRACT, "rb").read()
    original_extract_mode = stat.S_IMODE(os.stat(EXTRACT).st_mode)
    original_messy = open(MESSY, "rb").read()
    saved_outputs = {}
    for path in (EXTRACTED, CLEAN):
        saved_outputs[path] = open(path, "rb").read() if os.path.isfile(path) else None

    impl_path = f"/home/user/.extract_verifier_impl_{token}.py"
    marker = f"/tmp/extract_invoked_{token}"

    try:
        lines = [
            f"noise before [2025-03-04 05:06:07] alpha.{token}+tag@example.com after",
            f"{token} has no useful fields",
            f"beta-{token}@sample.org appeared at [2021-12-31 23:59:58]",
            f"two addresses first.{token}@example.net and second.{token}@example.net [2024-01-01 01:02:03]",
            f"two times [2020-01-01 00:00:00] and [2020-01-02 00:00:00] only.{token}@example.com",
            f"duplicate [2025-03-04 05:06:07] alpha.{token}+tag@example.com",
            f"punctuation: ({token}@sub.example.co.uk), [2023-07-08 09:10:11]!",
            "[2022-02-02 02:02:02] but no address",
        ]
        with open(MESSY, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

        expected_rows = expected_extract(lines)
        subprocess.run(["python3", EXTRACT], cwd="/tmp", check=True, timeout=30)
        assert os.path.isfile(EXTRACTED), "extract.py did not create extracted.csv"
        assert read_nonempty_lines(EXTRACTED) == expected_rows, (
            "extract.py did not correctly select lines containing exactly one timestamp "
            "and one email on a generated fixture"
        )

        # Wrap the submitted extractor so the pipeline must actually invoke extract.py.
        with open(impl_path, "wb") as f:
            f.write(original_extract)
        os.chmod(impl_path, original_extract_mode)
        wrapper = (
            "#!/usr/bin/env python3\n"
            "import os, sys\n"
            f"open({marker!r}, 'a').write('called\\n')\n"
            f"os.execv(sys.executable, [sys.executable, {impl_path!r}])\n"
        )
        with open(EXTRACT, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(EXTRACT, 0o755)

        for path in (EXTRACTED, CLEAN, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        subprocess.run([PIPELINE], cwd="/tmp", check=True, timeout=30)
        assert os.path.isfile(marker), "pipeline.sh did not run /home/user/extract.py"
        assert read_nonempty_lines(EXTRACTED) == expected_rows
        assert read_nonempty_lines(CLEAN) == sorted(set(expected_rows)), (
            "pipeline.sh did not chronologically sort and deduplicate generated output"
        )

        # Exercise the complete pipeline on a large file under a memory limit. A
        # streaming extractor succeeds, while reading the whole input into memory does not.
        large_first = f"[2019-01-02 03:04:05] first.{token}@large.example.com"
        large_last = f"last.{token}@large.example.org [2026-11-12 13:14:15]"
        with open(MESSY, "w", encoding="utf-8") as f:
            f.write(large_first + "\n")
            padding = "X" * 1023 + "\n"
            for _ in range(80 * 1024):
                f.write(padding)
            f.write(large_last + "\n")

        for path in (EXTRACTED, CLEAN, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        def limit_memory():
            limit = 64 * 1024 * 1024
            resource.setrlimit(resource.RLIMIT_AS, (limit, limit))

        subprocess.run(
            [PIPELINE], cwd="/tmp", check=True, timeout=60, preexec_fn=limit_memory
        )
        large_expected = [
            f"2019-01-02 03:04:05,first.{token}@large.example.com",
            f"2026-11-12 13:14:15,last.{token}@large.example.org",
        ]
        assert os.path.isfile(marker), "pipeline did not invoke extract.py on the large input"
        assert read_nonempty_lines(EXTRACTED) == large_expected
        assert read_nonempty_lines(CLEAN) == large_expected
    finally:
        with open(EXTRACT, "wb") as f:
            f.write(original_extract)
        os.chmod(EXTRACT, original_extract_mode)
        with open(MESSY, "wb") as f:
            f.write(original_messy)
        for path, content in saved_outputs.items():
            if content is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(content)
        for path in (impl_path, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
