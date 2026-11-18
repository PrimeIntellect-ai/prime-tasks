#!/bin/bash
mkdir -p /logs/verifier

verify() {
    test -f /home/user/analyzer.go || { echo "Missing /home/user/analyzer.go"; return 1; }
    test -s /home/user/analyzer.go || { echo "/home/user/analyzer.go is empty"; return 1; }

    GO111MODULE=off go build -o /tmp/submission_analyzer /home/user/analyzer.go || return 1
    test -x /tmp/submission_analyzer || return 1

    # Install a valid canonical fixture corresponding to the original assertions.
    python3 - <<'PY' || return 1
import struct

records = [
    (100, "rule_a", bytes([0x01, 0x02, 0x00, 0x04, 0x05, 0x00])),
    (101, "rule_b", bytes([0x01, 0x03, 0x00, 0x02, 0x03])),
    (102, "rule_c", bytes([0x01, 0x05, 0x00, 0x05])),
]
with open("/home/user/legacy_rules.bin", "wb") as f:
    f.write(struct.pack("<4sHI", b"PY2B", 1, len(records)))
    for rule_id, name, code in records:
        encoded_name = name.encode("utf-8")
        f.write(struct.pack("<IB", rule_id, len(encoded_name)))
        f.write(encoded_name)
        f.write(struct.pack("<I", len(code)))
        f.write(code)
PY

    rm -f /home/user/migration_report.json
    timeout 15s /tmp/submission_analyzer || return 1
    test -f /home/user/migration_report.json || return 1

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import json

def test_migration_report_exists_and_correct():
    file_path = "/home/user/migration_report.json"

    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you run the Go program and output to the correct path?"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} does not contain valid JSON."

    assert "rules_to_migrate" in data, "The key 'rules_to_migrate' is missing in the JSON output."

    rules = data["rules_to_migrate"]
    assert isinstance(rules, list), "'rules_to_migrate' should be a list."
    assert len(rules) == 2, f"Expected exactly 2 rules to migrate, but found {len(rules)}. Make sure you are correctly parsing instruction operands to avoid false positives."

    # Sort rules by ID to ensure deterministic checking regardless of output order
    rules_sorted = sorted(rules, key=lambda x: x.get("id", 0))

    rule_b = rules_sorted[0]
    assert rule_b.get("id") == 101, f"Expected rule ID 101, got {rule_b.get('id')}."
    assert rule_b.get("name") == "rule_b", f"Expected rule name 'rule_b', got {rule_b.get('name')}."
    assert rule_b.get("violating_opcodes") == [2, 3], f"Expected violating_opcodes [2, 3] for rule 101, got {rule_b.get('violating_opcodes')}."

    rule_c = rules_sorted[1]
    assert rule_c.get("id") == 102, f"Expected rule ID 102, got {rule_c.get('id')}."
    assert rule_c.get("name") == "rule_c", f"Expected rule name 'rule_c', got {rule_c.get('name')}."
    assert rule_c.get("violating_opcodes") == [5], f"Expected violating_opcodes [5] for rule 102, got {rule_c.get('violating_opcodes')}."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Exercise the compiled analyzer on fresh, unpredictable fixtures. Operand
    # bytes deliberately contain Python 2 opcode values and must be skipped.
    for round in 1 2; do
        ROUND="$round" python3 - <<'PY' || return 1
import os
import secrets
import struct

round_no = int(os.environ["ROUND"])
nonce = secrets.token_hex(6)
ids = set()
while len(ids) < 4:
    ids.add(secrets.randbelow(2**31) + 1)
ids = list(ids)

if round_no == 1:
    codes = [
        bytes([0x01, 0x02, 0x03, 0x04, 0x05, 0x02]),
        bytes([0x04, 0x02, 0x05, 0x05, 0x02, 0x03, 0x02]),
        bytes([0x01, 0x05, 0x02, 0x03]),
        bytes([0x04, 0x03, 0x02, 0x01, 0x02, 0x05]),
    ]
else:
    codes = [
        bytes([0x02, 0x02, 0x02]),
        bytes([0x01, 0x03, 0x05, 0x04, 0x02, 0x03]),
        bytes([0x05, 0x03, 0x05]),
        bytes([0x04, 0x05, 0x02, 0x01, 0x03, 0x05]),
    ]

records = [(ids[i], f"dynamic_{round_no}_{nonce}_{i}", codes[i]) for i in range(4)]
with open("/home/user/legacy_rules.bin", "wb") as f:
    f.write(struct.pack("<4sHI", b"PY2B", 100 + round_no, len(records)))
    for rule_id, name, code in records:
        encoded_name = name.encode("utf-8")
        f.write(struct.pack("<IB", rule_id, len(encoded_name)))
        f.write(encoded_name)
        f.write(struct.pack("<I", len(code)))
        f.write(code)
PY

        rm -f /home/user/migration_report.json
        timeout 15s /tmp/submission_analyzer || return 1
        test -f /home/user/migration_report.json || return 1

        python3 - <<'PY' || return 1
import json
import struct

with open("/home/user/legacy_rules.bin", "rb") as f:
    blob = f.read()

offset = 0
magic, version, count = struct.unpack_from("<4sHI", blob, offset)
offset += struct.calcsize("<4sHI")
assert magic == b"PY2B"
expected = []
for _ in range(count):
    rule_id, name_len = struct.unpack_from("<IB", blob, offset)
    offset += 5
    name = blob[offset:offset + name_len].decode("utf-8")
    offset += name_len
    code_len = struct.unpack_from("<I", blob, offset)[0]
    offset += 4
    code = blob[offset:offset + code_len]
    offset += code_len

    found = set()
    ip = 0
    while ip < len(code):
        opcode = code[ip]
        if opcode in (2, 3, 5):
            found.add(opcode)
        ip += 3 if opcode in (1, 4) else 1
    if found:
        expected.append({"id": rule_id, "name": name, "violating_opcodes": sorted(found)})

assert offset == len(blob)
with open("/home/user/migration_report.json", "r") as f:
    actual = json.load(f)
assert isinstance(actual, dict)
assert "rules_to_migrate" in actual
rules = actual["rules_to_migrate"]
assert isinstance(rules, list)
assert len(rules) == len(expected)
assert all(isinstance(rule, dict) for rule in rules)
assert len({rule.get("id") for rule in rules}) == len(rules)

actual_sorted = sorted(rules, key=lambda rule: rule.get("id", -1))
expected_sorted = sorted(expected, key=lambda rule: rule["id"])
for got, want in zip(actual_sorted, expected_sorted):
    assert got.get("id") == want["id"]
    assert got.get("name") == want["name"]
    assert got.get("violating_opcodes") == want["violating_opcodes"]
PY
    done
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
