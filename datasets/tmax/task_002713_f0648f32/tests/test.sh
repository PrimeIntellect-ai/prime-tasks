#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess

SCRIPT = "/home/user/build_dataset.sh"
CSV = "/home/user/processed/dataset.csv"
DEMOGRAPHICS = "/home/user/raw/demographics.txt"
REVIEWS = "/home/user/raw/reviews.txt"
EXPECTED_INITIAL = [
    "uid,age,country,tokenized_review",
    "101,25,US,this-is-awesome",
    "104,40,FR,works-well-but-a-bit-pricey",
    "108,29,JP,100-perfect",
]


def read_nonempty_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def test_01_original_assertions_and_script_type():
    assert os.path.isfile(SCRIPT), f"The bash script {SCRIPT} does not exist."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), f"{SCRIPT} is not a regular file."
    assert os.path.isdir("/home/user/processed"), "The output directory /home/user/processed does not exist."
    assert os.path.isfile(CSV), f"The output file {CSV} does not exist."

    actual_lines = read_nonempty_lines(CSV)
    assert actual_lines[0] == EXPECTED_INITIAL[0], f"Expected header '{EXPECTED_INITIAL[0]}', but got '{actual_lines[0]}'."
    assert len(actual_lines) == len(EXPECTED_INITIAL), f"Expected {len(EXPECTED_INITIAL)} lines in output, but got {len(actual_lines)}."
    for i in range(1, len(EXPECTED_INITIAL)):
        assert actual_lines[i] == EXPECTED_INITIAL[i], f"Expected row {i} to be '{EXPECTED_INITIAL[i]}', but got '{actual_lines[i]}'."

    with open(SCRIPT, "r", encoding="utf-8", errors="strict") as f:
        source = f.read()
    assert "\x00" not in source, "The submitted script is not a text shell script."
    first = source.splitlines()[0] if source.splitlines() else ""
    if first.startswith("#!"):
        assert re.search(r"(?:ba|da|k|z)?sh\b", first), "The script shebang must select a shell."

    active_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    forbidden = re.compile(
        r"(?im)(?:^\s*|[;&|(`]\s*|\b(?:then|do|if|elif|else|command|exec|env|sudo|time)\s+)"
        r"(?:/[A-Za-z0-9_./+-]+/)?"
        r"(?:python\d*(?:\.\d+)?|perl|ruby|node(?:js)?|php|lua|rscript|julia|java|javac|"
        r"gcc|g\+\+|clang|rustc|dotnet|mono)\b"
    )
    assert not forbidden.search(active_source), "The pipeline invokes a prohibited programming-language tool."

    syntax = subprocess.run(
        ["/bin/bash", "-n", SCRIPT], text=True, capture_output=True, timeout=10
    )
    assert syntax.returncode == 0, f"Invalid Bash syntax:\n{syntax.stderr}"


def tokenize(text):
    text = text.lower()
    text = re.sub(r"[^a-z0-9 ]", "", text)
    text = re.sub(r" +", "-", text)
    return text.strip("-")


def expected_output(demographic_rows, review_rows):
    demographics = {}
    for uid, age, country in demographic_rows:
        if not re.fullmatch(r"[0-9]+", age):
            continue
        if int(age) < 18 or country == "":
            continue
        demographics.setdefault(uid, []).append((age, country))

    result = []
    for uid, review, score in review_rows:
        if not re.fullmatch(r"[0-9]+", score) or int(score) <= 3:
            continue
        cleaned = tokenize(review)
        if not cleaned:
            continue
        for age, country in demographics.get(uid, []):
            result.append((int(uid), f"{uid},{age},{country},{cleaned}"))
    result.sort(key=lambda item: item[0])
    return ["uid,age,country,tokenized_review"] + [line for _, line in result]


def write_inputs(demographic_rows, review_rows):
    with open(DEMOGRAPHICS, "w", encoding="utf-8", newline="\n") as f:
        f.write("uid|age|country\n")
        for row in demographic_rows:
            f.write("|".join(row) + "\n")
    with open(REVIEWS, "w", encoding="utf-8", newline="\n") as f:
        f.write("uid\treview_text\tscore\n")
        for row in review_rows:
            f.write("\t".join(row) + "\n")


def make_case():
    base = 200000 + secrets.randbelow(500000)
    ids = {name: str(base + offset) for name, offset in {
        "late": 20, "early": 3, "young": 11, "nocountry": 8,
        "emptytext": 15, "demo_only": 30, "review_only": 6
    }.items()}
    marker = "".join(chr(ord("a") + secrets.randbelow(26)) for _ in range(12))

    demographics = [
        (ids["late"], "18", "NZ"),
        (ids["young"], "17", "CA"),
        (ids["demo_only"], "44", "DE"),
        (ids["early"], "27", "US"),
        (ids["nocountry"], "31", ""),
        (ids["emptytext"], "52", "FR"),
    ]
    reviews = [
        (ids["review_only"], "Ghost record", "9"),
        (ids["late"], f"  {marker.upper()}, Mixed CASE!! 42  ", "4"),
        (ids["young"], "Too young", "5"),
        (ids["early"], "A___B...  900%", "10"),
        (ids["nocountry"], "No country", "5"),
        (ids["emptytext"], "!!! ___ %%%", "5"),
        (ids["late"], "Low score must disappear", "3"),
    ]
    return demographics, reviews


def run_and_check(demographics, reviews, remove_output_dir=False):
    write_inputs(demographics, reviews)
    if remove_output_dir:
        subprocess.run(["/bin/rm", "-rf", "/home/user/processed"], check=True)

    completed = subprocess.run(
        ["/bin/bash", SCRIPT],
        cwd="/home/user",
        text=True,
        capture_output=True,
        timeout=20,
        env={**os.environ, "LC_ALL": "C"},
    )
    assert completed.returncode == 0, (
        f"The script failed on valid alternate inputs.\nstdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert os.path.isdir("/home/user/processed"), "The script did not create /home/user/processed."
    assert os.path.isfile(CSV), "The script did not create dataset.csv."
    actual = read_nonempty_lines(CSV)
    expected = expected_output(demographics, reviews)
    assert actual == expected, f"Alternate-input output mismatch.\nExpected: {expected}\nActual: {actual}"


def test_02_execute_pipeline_on_altered_inputs():
    demographics, reviews = make_case()
    run_and_check(demographics, reviews, remove_output_dir=True)

    # A second independently generated case verifies that the script overwrites
    # its output and actually responds to changed raw data on every execution.
    demographics, reviews = make_case()
    run_and_check(demographics, reviews, remove_output_dir=False)
TEST_EOF

if cd / && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
