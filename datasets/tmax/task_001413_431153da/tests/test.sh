#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import shlex
import stat
import subprocess


def test_generate_payload_sh_exists_and_executable():
    path = "/home/user/generate_payload.sh"
    assert os.path.exists(path), f"{path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."


def test_generate_payload_sh_output():
    path = "/home/user/generate_payload.sh"
    assert os.path.exists(path), f"{path} does not exist."

    expected_output = "01:416c7068614e6f6465-QWxwaGFOb2Rl_02|02:426574614e6f6465-QmV0YU5vZGU=_03|03:47616d6d615465726d696e616c-R2FtbWFUZXJtaW5hbA==_00"

    result = subprocess.run([path], capture_output=True, text=True)
    assert result.stdout.strip() == expected_output, f"Output of {path} does not match the expected payload."


def test_generate_payload_performs_encoding():
    path = "/home/user/generate_payload.sh"
    original = open(path, "rb").read()
    original_mode = stat.S_IMODE(os.stat(path).st_mode)

    values = ["DynA" + secrets.token_hex(5), "DynB" + secrets.token_hex(6), "DynC" + secrets.token_hex(7)]
    modified = original
    for old, new in zip((b"AlphaNode", b"BetaNode", b"GammaTerminal"), (v.encode() for v in values)):
        modified = modified.replace(old, new)

    assert modified != original, "generate_payload.sh does not contain the source data needed to perform the translation."

    try:
        with open(path, "wb") as f:
            f.write(modified)
        os.chmod(path, original_mode)

        expected_nodes = []
        for node_id, data, child_id in zip(("01", "02", "03"), values, ("02", "03", "00")):
            raw = data.encode("utf-8")
            expected_nodes.append(f"{node_id}:{raw.hex()}-{base64.b64encode(raw).decode()}_{child_id}")

        result = subprocess.run([path], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == "|".join(expected_nodes), \
            "generate_payload.sh does not dynamically encode the translated node data."
    finally:
        with open(path, "wb") as f:
            f.write(original)
        os.chmod(path, original_mode)


def test_ci_pipeline_sh_exists_and_executable():
    path = "/home/user/ci_pipeline.sh"
    assert os.path.exists(path), f"{path} does not exist."
    assert os.path.isfile(path), f"{path} is not a file."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."


def test_ci_artifact_log_content():
    pipeline = "/home/user/ci_pipeline.sh"
    path = "/home/user/ci_artifact.log"
    if os.path.lexists(path):
        os.remove(path)

    result = subprocess.run([pipeline], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    assert os.path.exists(path), f"{path} does not exist. Did you run ci_pipeline.sh?"
    assert os.path.isfile(path), f"{path} is not a file."

    expected_content = (
        "PIPELINE_START\n"
        "01:416c7068614e6f6465-QWxwaGFOb2Rl_02|02:426574614e6f6465-QmV0YU5vZGU=_03|03:47616d6d615465726d696e616c-R2FtbWFUZXJtaW5hbA==_00\n"
        "GammaTerminal\n"
        "PIPELINE_SUCCESS"
    )

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"Content of {path} does not match the expected format."


def make_node(node_id, data, child_id):
    raw = data.encode("utf-8")
    return f"{node_id}:{raw.hex()}-{base64.b64encode(raw).decode()}_{child_id}"


def test_ci_pipeline_parses_generated_payload_and_terminal_node():
    generator = "/home/user/generate_payload.sh"
    pipeline = "/home/user/ci_pipeline.sh"
    artifact = "/home/user/ci_artifact.log"
    original = open(generator, "rb").read()
    original_mode = stat.S_IMODE(os.stat(generator).st_mode)

    try:
        for _ in range(2):
            first = "First" + secrets.token_hex(6)
            terminal = "Terminal" + secrets.token_hex(8)
            last = "Last" + secrets.token_hex(5)

            # The terminal node is deliberately in the middle, so the pipeline
            # must inspect CHILD_ID rather than decode a fixed or final node.
            payload = "|".join([
                make_node("A1", first, "B2"),
                make_node("B2", terminal, "00"),
                make_node("C3", last, "D4"),
            ])
            replacement = "#!/bin/bash\nprintf '%s\\n' " + shlex.quote(payload) + "\n"
            with open(generator, "w") as f:
                f.write(replacement)
            os.chmod(generator, 0o755)

            if os.path.lexists(artifact):
                os.remove(artifact)
            result = subprocess.run([pipeline], capture_output=True, text=True, timeout=10)
            assert result.returncode == 0, result.stderr
            assert os.path.isfile(artifact), "ci_pipeline.sh did not create ci_artifact.log"

            expected = f"PIPELINE_START\n{payload}\n{terminal}\nPIPELINE_SUCCESS"
            with open(artifact, "r") as f:
                actual = f.read().strip()
            assert actual == expected, \
                "ci_pipeline.sh did not execute the generator and parse/decode the terminal node."
    finally:
        with open(generator, "wb") as f:
            f.write(original)
        os.chmod(generator, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
