#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile


def test_sensor_processor_cpp_exists():
    """Verify that the C++ source exists, compiles, and implements threshold filtering."""
    cpp_path = "/home/user/edge_app/sensor_processor.cpp"
    assert os.path.isfile(cpp_path), f"File {cpp_path} is missing."

    binary = "/tmp/sensor_processor_verifier"
    result = subprocess.run(
        ["g++", "-std=c++17", cpp_path, "-o", binary],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"sensor_processor.cpp did not compile: {result.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK)

    default_input = (
        "2000000000,negative,-1.5\n"
        "2000000001,zero,0.0\n"
        "2000000002,small,0.125\n"
        "2000000003,large,73.4\n"
    )
    env = os.environ.copy()
    env.pop("MIN_THRESHOLD", None)
    run = subprocess.run([binary], input=default_input, capture_output=True, text=True, env=env)
    assert run.returncode == 0, f"Processor failed with default threshold: {run.stderr}"
    assert run.stdout == (
        "2000000002,small,0.125\n"
        "2000000003,large,73.4\n"
    ), "Processor did not apply the default threshold of 0.0 correctly."

    threshold_input = (
        "2100000000,equal,10.25\n"
        "2100000001,below,10.2499\n"
        "2100000002,above,10.2501\n"
        "2100000003,high,99.75\n"
    )
    env["MIN_THRESHOLD"] = "10.25"
    run = subprocess.run([binary], input=threshold_input, capture_output=True, text=True, env=env)
    assert run.returncode == 0, f"Processor failed with MIN_THRESHOLD set: {run.stderr}"
    assert run.stdout == (
        "2100000002,above,10.2501\n"
        "2100000003,high,99.75\n"
    ), "Processor must output only values strictly greater than MIN_THRESHOLD."


def run_pipeline_and_check(raw_content, expected):
    script_path = "/home/user/edge_app/run_pipeline.sh"
    raw_path = "/home/user/data/raw_sensors.log"
    output_path = "/home/user/data/processed_sensors.txt"
    processor_path = "/home/user/edge_app/processor"

    with open(raw_path, "w") as f:
        f.write(raw_content)
    if os.path.exists(output_path):
        os.remove(output_path)
    if os.path.exists(processor_path):
        os.remove(processor_path)

    result = subprocess.run(["/bin/bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"run_pipeline.sh failed with error: {result.stderr}"
    assert os.path.isfile(processor_path), "run_pipeline.sh did not create the processor executable."
    assert os.access(processor_path, os.X_OK), "The generated processor is not executable."
    assert os.path.isfile(output_path), f"Output file {output_path} was not created."
    with open(output_path, "r") as f:
        content = f.read().strip()
    assert content == expected, (
        f"Content of {output_path} does not match expected output.\n"
        f"Expected:\n{expected}\nGot:\n{content}"
    )


def test_run_pipeline_script():
    """Run the pipeline on the original fixture and independently chosen inputs."""
    script_path = "/home/user/edge_app/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    raw_path = "/home/user/data/raw_sensors.log"
    with open(raw_path, "rb") as f:
        original_raw = f.read()

    try:
        # Preserve the original fixed-fixture assertion.
        fixed_raw = (
            "1690000000,temp_01,42.1\n"
            "1690000001,temp_02,46.0\n"
            "1690000002,press_01,100.5\n"
            "1690000003,temp_01,44.9\n"
            "1690000004,temp_03,45.6\n"
        )
        expected_output = (
            "[temp_02] recorded 46.0\n"
            "[press_01] recorded 100.5\n"
            "[temp_03] recorded 45.6"
        )
        run_pipeline_and_check(fixed_raw, expected_output)

        # Different data prevents a script from emitting the fixed expected text.
        dynamic_raw_1 = (
            "1800000000,humidity_west,45.5\n"
            "1800000001,humidity_east,45.5001\n"
            "1800000002,vibration_7,88.75\n"
            "1800000003,cold_probe,-3.0\n"
            "1800000004,flow_main,46.125\n"
        )
        run_pipeline_and_check(
            dynamic_raw_1,
            "[humidity_east] recorded 45.5001\n"
            "[vibration_7] recorded 88.75\n"
            "[flow_main] recorded 46.125",
        )

        dynamic_raw_2 = (
            "1900000000,node_A,1000.0\n"
            "1900000001,node_B,1.0\n"
            "1900000002,node_C,47.25\n"
            "1900000003,node_D,45.50\n"
        )
        run_pipeline_and_check(
            dynamic_raw_2,
            "[node_A] recorded 1000.0\n[node_C] recorded 47.25",
        )
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)


def test_system_fstab():
    """Verify the custom fstab entry is correct."""
    fstab_path = "/home/user/system_fstab"
    assert os.path.isfile(fstab_path), f"File {fstab_path} is missing."

    with open(fstab_path, "r") as f:
        lines = f.readlines()

    found_entry = False
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6:
            if (parts[0] == "/home/user/sensor_disk.img" and
                parts[1] == "/home/user/data" and
                parts[2] == "ext4" and
                parts[3] == "rw,user,noatime" and
                parts[4] == "0" and
                parts[5] == "2"):
                found_entry = True
                break

    assert found_entry, "Correct fstab entry for sensor_disk.img was not found in /home/user/system_fstab."


def parse_nginx(content):
    """Parse enough Nginx syntax to validate block nesting and directive placement."""
    uncommented = re.sub(r"#[^\n]*", "", content)
    tokens = re.findall(r"[{};]|[^\s{};]+", uncommented)

    def parse_scope(index, expect_close):
        entries = []
        while index < len(tokens):
            if tokens[index] == "}":
                assert expect_close, "Unexpected closing brace in lb.conf."
                return entries, index + 1

            header = []
            while index < len(tokens) and tokens[index] not in ("{", "}", ";"):
                header.append(tokens[index])
                index += 1
            assert header, "Empty or malformed Nginx statement."
            assert index < len(tokens), "Unterminated Nginx statement."

            if tokens[index] == ";":
                entries.append(("directive", header, []))
                index += 1
            elif tokens[index] == "{":
                children, index = parse_scope(index + 1, True)
                entries.append(("block", header, children))
            else:
                raise AssertionError("Malformed Nginx configuration near closing brace.")

        assert not expect_close, "Unclosed block in lb.conf."
        return entries, index

    parsed, end = parse_scope(0, False)
    assert end == len(tokens)
    return parsed


def directives(entries, name):
    return [header for kind, header, _ in entries if kind == "directive" and header and header[0] == name]


def blocks(entries, name):
    return [(header, children) for kind, header, children in entries if kind == "block" and header and header[0] == name]


def test_nginx_lb_conf():
    """Verify required directives are in valid, correctly nested Nginx blocks."""
    conf_path = "/home/user/edge_app/lb.conf"
    assert os.path.isfile(conf_path), f"File {conf_path} is missing."

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert re.search(r"upstream\s+sensor_backends\s*\{", content), "upstream 'sensor_backends' block missing."
    assert "127.0.0.1:9001" in content, "Backend 127.0.0.1:9001 missing from upstream block."
    assert "127.0.0.1:9002" in content, "Backend 127.0.0.1:9002 missing from upstream block."
    assert re.search(r"server\s*\{", content), "server block missing."
    assert re.search(r"listen\s+8080\s*;", content), "listen 8080 directive missing."
    assert re.search(r"location\s+/\s*\{", content), "location / block missing."
    assert re.search(r"proxy_pass\s+http://sensor_backends\s*;", content), "proxy_pass directive missing or incorrect."

    parsed = parse_nginx(content)

    upstream_matches = [
        children for header, children in blocks(parsed, "upstream")
        if header == ["upstream", "sensor_backends"]
    ]
    assert upstream_matches, "A structural upstream sensor_backends block is required."
    assert any(
        ["server", "127.0.0.1:9001"] in directives(children, "server") and
        ["server", "127.0.0.1:9002"] in directives(children, "server")
        for children in upstream_matches
    ), "Both backends must be server directives inside upstream sensor_backends."

    valid_server = False
    for header, children in blocks(parsed, "server"):
        if header != ["server"]:
            continue
        if ["listen", "8080"] not in directives(children, "listen"):
            continue
        for location_header, location_children in blocks(children, "location"):
            if (location_header == ["location", "/"] and
                    ["proxy_pass", "http://sensor_backends"] in directives(location_children, "proxy_pass")):
                valid_server = True
                break
    assert valid_server, (
        "A server block must listen on 8080 and contain location / with "
        "proxy_pass http://sensor_backends."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
