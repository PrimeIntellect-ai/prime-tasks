#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import random
import subprocess

BUGGY_SOURCE = '''def parse_line(line):
    parts = line.split(',')
    if len(parts) != 2:
        return "INVALID"
    try:
        lat_str = parts[0]
        lon_str = parts[1]
        lat, lon = round(float(lat_str), 4), round(float(lon_str), 4)
        return f"({lat}, {lon})"
    except ValueError:
        return "INVALID"
'''


def generate_inputs(n=2500):
    random.seed(42)
    inputs = []
    for _ in range(n):
        is_invalid = random.random() < 0.05
        if is_invalid:
            choices = [
                "just a string",
                "12.34",
                "12.34, 56.78, 90.12",
                "abc, def",
                "",
            ]
            inputs.append(random.choice(choices))
            continue

        lat = random.uniform(-90.0, 90.0)
        lon = random.uniform(-180.0, 180.0)
        prec1 = random.randint(1, 9)
        prec2 = random.randint(1, 9)

        s_lat = f"{lat:.{prec1}f}"
        s_lon = f"{lon:.{prec2}f}"

        is_corrupted = random.random() < 0.3
        if is_corrupted:
            if random.random() < 0.5:
                if s_lat.startswith("0."):
                    s_lat = s_lat[1:]
                elif s_lat.startswith("-0."):
                    s_lat = "-" + s_lat[2:]
            if random.random() < 0.5:
                if s_lon.startswith("0."):
                    s_lon = s_lon[1:]
                elif s_lon.startswith("-0."):
                    s_lon = "-" + s_lon[2:]

            sep = random.choice([",", " , ", "\t,\t", ",  \t", " ,"])
            s = s_lat + sep + s_lon
            if random.random() < 0.5:
                s = random.choice([" ", "\t", "  \t "]) + s
            if random.random() < 0.5:
                s = s + random.choice([" ", "\t", "  \t "])
        else:
            s = f"{s_lat}, {s_lon}"

        inputs.append(s)
    return inputs


def expected_output(line):
    parts = line.split(',')
    if len(parts) != 2:
        return "INVALID"
    try:
        lat = float(parts[0].strip())
        lon = float(parts[1].strip())
        return f"({lat}, {lon})"
    except ValueError:
        return "INVALID"


def test_vendored_package_was_fixed():
    parser_path = "/app/geoparse/parser.py"
    assert os.path.isfile(parser_path), f"Vendored parser not found at {parser_path}"
    assert not os.path.islink(parser_path), "Vendored parser must be a real file"

    with open(parser_path, "r", encoding="utf-8") as f:
        source = f.read()
    assert source != BUGGY_SOURCE, "Vendored parser was not modified"

    spec = importlib.util.spec_from_file_location("geoparse_parser_under_test", parser_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "parse_line", None)), "parse_line is missing"

    inputs = generate_inputs(2500)
    inputs.extend([
        "45.123456789, -122.987654321",
        "  -.987  ,\t.123456789\t",
        "not coordinates",
    ])
    for inp in inputs:
        assert module.parse_line(inp) == expected_output(inp), (
            f"Vendored parser mismatch on input: {inp!r}\n"
            f"Expected: {expected_output(inp)!r}\n"
            f"Got: {module.parse_line(inp)!r}"
        )


def test_fixed_parser_fuzz_equivalence():
    agent_script = "/home/user/fixed_parser.py"
    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert not os.path.islink(agent_script), "Agent script must be a standalone regular file"

    inputs = generate_inputs(2500)
    for inp in inputs:
        agent_proc = subprocess.run(
            ["python3", "-I", "-S", agent_script, inp],
            capture_output=True,
            text=True,
            timeout=5,
        )
        assert agent_proc.returncode == 0, (
            f"Agent script failed on input {inp!r}: {agent_proc.stderr!r}"
        )

        expected = expected_output(inp)
        actual = agent_proc.stdout.strip()
        assert expected == actual, (
            f"Output mismatch on input: {inp!r}\n"
            f"Expected: {expected!r}\n"
            f"Got: {actual!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
