#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_UP
import xml.etree.ElementTree as ET

SOURCE = "/home/user/process.cpp"
EXECUTABLE = "/home/user/process"
INPUT = "/home/user/locales/en_US.csv"
OUTPUT = "/home/user/locales/es_ES.xml"

original_rows = [
    ("balance", "Your current balance is $150.00.", "User query from john.doe@email.com"),
    ("fee", "A transaction fee of $1.50 applies.", "Alert system@fintech.net"),
    ("promo", "Get $50 off your next purchase of $200.00!", "Approved by marketing_lead@promo.co.uk"),
]

expected_original = """<locale>
  <string id="balance" notes="User query from ***@email.com">Your current balance is 127.50€.</string>
  <string id="fee" notes="Alert ***@fintech.net">A transaction fee of 1.28€ applies.</string>
  <string id="promo" notes="Approved by ***@promo.co.uk">Get 42.50€ off your next purchase of 170.00€!</string>
</locale>"""

dynamic_rows = [
    ("rounding", "Half $2.50, whole $10, and small $0.50.",
     "Mail alpha.beta+tag@sub.example.com then z_9@foo.co.uk"),
    ("unchanged", "No currency appears here.", "No contact provided"),
    ("another", "The amount is $123.45.", "Owner person42@test.example"),
]


def write_csv(rows):
    def quote(value):
        return '"' + value.replace('"', '""') + '"'

    with open(INPUT, "w", encoding="utf-8", newline="") as f:
        f.write("key,text,comment\n")
        for key, text, comment in rows:
            f.write(f"{key},{quote(text)},{quote(comment)}\n")


def derive_expected(rows):
    email_re = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
    currency_re = re.compile(r"\$(\d+(?:\.\d{2})?)")

    def mask(comment):
        return email_re.sub(lambda m: "***@" + m.group(1), comment)

    def convert(text):
        def replacement(match):
            value = Decimal(match.group(1)) * Decimal("0.85")
            value = value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
            return f"{value:.2f}€"
        return currency_re.sub(replacement, text)

    lines = ["<locale>"]
    for key, text, comment in rows:
        lines.append(f'  <string id="{key}" notes="{mask(comment)}">{convert(text)}</string>')
    lines.append("</locale>")
    return "\n".join(lines)


def run_program(executable):
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=15, text=True
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{executable} did not generate {OUTPUT}"


def test_output_xml_exists():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."


def test_output_xml_content():
    with open(OUTPUT, "r", encoding="utf-8") as f:
        content = f.read().strip()

    actual_lines = [line.strip("\r\n") for line in content.splitlines()]
    expected_lines = [line.strip("\r\n") for line in expected_original.splitlines()]
    assert actual_lines == expected_lines, (
        "The output XML content does not match the expected format or values."
    )


def test_xml_is_valid():
    try:
        tree = ET.parse(OUTPUT)
        root = tree.getroot()
    except ET.ParseError as e:
        assert False, f"Output file is not valid XML: {e}"

    assert root.tag == "locale", "Root element must be <locale>."
    strings = root.findall("string")
    assert len(strings) == 3, "There should be exactly 3 <string> elements."

    expected_data = [
        {"id": "balance", "notes": "User query from ***@email.com", "text": "Your current balance is 127.50€."},
        {"id": "fee", "notes": "Alert ***@fintech.net", "text": "A transaction fee of 1.28€ applies."},
        {"id": "promo", "notes": "Approved by ***@promo.co.uk", "text": "Get 42.50€ off your next purchase of 170.00€!"},
    ]
    for i, expected in enumerate(expected_data):
        assert strings[i].attrib.get("id") == expected["id"], f"Expected id '{expected['id']}'"
        assert strings[i].attrib.get("notes") == expected["notes"], f"Expected notes '{expected['notes']}'"
        assert strings[i].text == expected["text"], f"Expected text '{expected['text']}'"


def assert_exact(expected):
    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual = f.read().strip()
    assert actual.splitlines() == expected.splitlines(), "Generated XML did not match derived results"
    root = ET.parse(OUTPUT).getroot()
    assert root.tag == "locale"


def main():
    assert os.path.isfile(SOURCE), f"Required C++ source {SOURCE} does not exist"
    assert os.path.getsize(SOURCE) > 0, f"Required C++ source {SOURCE} is empty"
    assert os.path.isfile(EXECUTABLE), f"Required executable {EXECUTABLE} does not exist"
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable"

    rebuilt = os.path.join(tempfile.mkdtemp(prefix="verify_process_"), "process")
    compile_result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, text=True
    )
    assert compile_result.returncode == 0, f"process.cpp did not compile: {compile_result.stderr}"

    try:
        for executable in (EXECUTABLE, rebuilt):
            write_csv(original_rows)
            run_program(executable)
            test_output_xml_exists()
            test_output_xml_content()
            test_xml_is_valid()

            write_csv(dynamic_rows)
            run_program(executable)
            assert_exact(derive_expected(dynamic_rows))
    finally:
        write_csv(original_rows)

    # Leave the required final artifact generated by the submitted executable.
    run_program(EXECUTABLE)
    test_output_xml_exists()
    test_output_xml_content()
    test_xml_is_valid()


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
