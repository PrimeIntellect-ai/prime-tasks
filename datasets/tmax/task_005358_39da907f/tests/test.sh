#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import json
import re


def expected_outputs(lines):
    matrix = [[3, -1], [2, 4]]
    outputs = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            decoded_line = re.sub(
                r'\\u([0-9a-fA-F]{4})',
                lambda m: chr(int(m.group(1), 16)),
                line,
            )
            data = json.loads(decoded_line)
            if 'coordinates' in data and 'x' in data['coordinates'] and 'y' in data['coordinates']:
                x = data['coordinates']['x']
                y = data['coordinates']['y']
                if isinstance(x, (int, float)) and isinstance(y, (int, float)):
                    outputs.append({
                        "original_x": x,
                        "original_y": y,
                        "transformed_x": matrix[0][0] * x + matrix[0][1] * y,
                        "transformed_y": matrix[1][0] * x + matrix[1][1] * y,
                    })
        except Exception:
            pass
    return outputs


def test_fuzz_equivalence():
    agent_script = "/home/user/process_telemetry.py"
    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"

    random.seed(1337)
    lines = []
    for _ in range(5000):
        choice = random.random()
        if choice < 0.5:
            x = random.randint(-1000, 1000)
            y = random.randint(-1000, 1000)
            s = f'{{"c\\u006Fordinates": {{"x": {x}, "y": {y}}}, "val": "t\\u0065st"}}'
        elif choice < 0.7:
            x = random.randint(-1000, 1000)
            y = random.randint(-1000, 1000)
            s = f'{{"coordinates": {{"x": {x}, "y": {y}}}, "broken": \\u0022value\\u0022 }}'
        elif choice < 0.8:
            x = random.randint(-1000, 1000)
            y = random.randint(-1000, 1000)
            s = f'{{"coordinates": {{"x": {x}, "y": {y}}}, "broken": \\u0041 }}'
        elif choice < 0.9:
            s = '{"other_data": {"x": 1, "y": 2}}'
        else:
            s = "".join(random.choices(string.ascii_letters + "{}[],:\\\" ", k=random.randint(50, 200)))
        lines.append(s)

    input_data = "\n".join(lines) + "\n"
    expected = expected_outputs(lines)

    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=input_data,
        text=True,
        capture_output=True,
    )

    assert agent_proc.returncode == 0, (
        f"Agent script failed with return code {agent_proc.returncode}\n"
        f"Stderr: {agent_proc.stderr}"
    )

    output_lines = agent_proc.stdout.strip().split('\n') if agent_proc.stdout.strip() else []
    assert len(output_lines) == len(expected), (
        f"Output line count mismatch. Expected {len(expected)}, got {len(output_lines)}. "
        "Are you silently dropping invalid lines as requested?"
    )

    for i, (actual_line, expected_object) in enumerate(zip(output_lines, expected)):
        try:
            actual_object = json.loads(actual_line)
        except Exception as exc:
            assert False, f"Output line {i + 1} is not valid JSON: {exc}\nGot: {actual_line}"
        assert actual_object == expected_object, (
            f"Mismatch at output line {i + 1}:\n"
            f"Expected: {expected_object!r}\nGot:      {actual_object!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
