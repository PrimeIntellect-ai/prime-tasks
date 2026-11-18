#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_c_source_and_executable_exist():
    c_source = "/home/user/etl_step.c"
    executable = "/home/user/etl_step"

    assert os.path.isfile(c_source), f"C source file {c_source} is missing."
    assert os.path.isfile(executable), f"Executable file {executable} is missing."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {executable} is not a compiled native executable."


def test_report_content():
    corpus_path = "/home/user/corpus.txt"
    template_path = "/home/user/report.tmpl"
    report_path = "/home/user/report.txt"

    assert os.path.isfile(corpus_path), f"Input file {corpus_path} is missing."
    assert os.path.isfile(template_path), f"Template file {template_path} is missing."
    assert os.path.isfile(report_path), f"Output file {report_path} is missing."

    # Compute expected statistics
    with open(corpus_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    total_lines = len(lines)
    total_words = 0
    max_len = 0

    for line in lines:
        # split() without arguments splits by all whitespace, matching the C requirement
        # for standard ASCII whitespace (space, tab, newline).
        words = line.split()
        total_words += len(words)
        for word in words:
            if len(word) > max_len:
                max_len = len(word)

    # Generate expected report
    with open(template_path, "r", encoding="utf-8") as f:
        template_content = f.read()

    expected_report = template_content.replace("{{LINES}}", str(total_lines))
    expected_report = expected_report.replace("{{WORDS}}", str(total_words))
    expected_report = expected_report.replace("{{MAX_LEN}}", str(max_len))

    # Read actual report
    with open(report_path, "r", encoding="utf-8") as f:
        actual_report = f.read()

    assert actual_report == expected_report, (
        f"Content of {report_path} does not match expected output.\n"
        f"Expected:\n{expected_report}\n"
        f"Actual:\n{actual_report}"
    )


def test_executable_and_submitted_source_process_unseen_inputs():
    corpus_path = "/home/user/corpus.txt"
    template_path = "/home/user/report.tmpl"
    report_path = "/home/user/report.txt"
    executable = "/home/user/etl_step"
    rebuilt = "/tmp/etl_step_rebuilt"

    subprocess.run(
        ["gcc", "/home/user/etl_step.c", "-O2", "-o", rebuilt],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted C source did not build a native executable."

    saved_corpus = open(corpus_path, "rb").read()
    saved_template = open(template_path, "rb").read()
    saved_report = open(report_path, "rb").read()

    alphabet = list("abcdefghijklmnopqrstuvwxyz") + ["é", "界", "🙂", "́", "\u00a0"]

    try:
        cases = []
        for case_number in range(4):
            line_count = 3 + secrets.randbelow(6)
            words_by_line = []
            for line_number in range(line_count):
                word_count = secrets.randbelow(6)
                if line_number == 0:
                    word_count += 1
                words = []
                for _ in range(word_count):
                    length = 1 + secrets.randbelow(18)
                    words.append("".join(secrets.choice(alphabet) for _ in range(length)))
                words_by_line.append(words)

            # Guarantee Unicode, an embedded non-ASCII whitespace code point, and
            # a runtime-varying candidate for the longest word.
            words_by_line[0].append("界🙂é" + "x" * (8 + secrets.randbelow(18)))
            words_by_line[-1].append("a\u00a0b")

            rendered_lines = []
            for words in words_by_line:
                line = ""
                for index, word in enumerate(words):
                    if index:
                        line += secrets.choice([" ", "\t", "  ", " \t"])
                    line += word
                rendered_lines.append(line)

            corpus = "\n".join(rendered_lines) + "\n"
            total_words = sum(len(words) for words in words_by_line)
            max_len = max((len(word) for words in words_by_line for word in words), default=0)
            nonce = secrets.token_hex(12)
            template = (
                "Dynamic case " + nonce + "\n"
                "lines={{LINES}}; words={{WORDS}}; max={{MAX_LEN}}\n"
                "again {{MAX_LEN}}/{{WORDS}}/{{LINES}}\n"
            )
            expected = template.replace("{{LINES}}", str(line_count))
            expected = expected.replace("{{WORDS}}", str(total_words))
            expected = expected.replace("{{MAX_LEN}}", str(max_len))
            cases.append((corpus, template, expected, case_number))

        for program in (executable, rebuilt):
            for corpus, template, expected, case_number in cases:
                with open(corpus_path, "w", encoding="utf-8", newline="") as f:
                    f.write(corpus)
                with open(template_path, "w", encoding="utf-8", newline="") as f:
                    f.write(template)
                if os.path.exists(report_path):
                    os.unlink(report_path)

                result = subprocess.run(
                    [program],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                )
                assert result.returncode == 0, (
                    f"{program} failed on dynamic case {case_number}: "
                    f"{result.stderr.decode('utf-8', errors='replace')}"
                )
                assert os.path.isfile(report_path), f"{program} did not create report.txt."
                with open(report_path, "r", encoding="utf-8") as f:
                    actual = f.read()
                assert actual == expected, (
                    f"{program} produced an incorrect report on dynamic case {case_number}.\n"
                    f"Expected:\n{expected}\nActual:\n{actual}"
                )
    finally:
        with open(corpus_path, "wb") as f:
            f.write(saved_corpus)
        with open(template_path, "wb") as f:
            f.write(saved_template)
        with open(report_path, "wb") as f:
            f.write(saved_report)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
