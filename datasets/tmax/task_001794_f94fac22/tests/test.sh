#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import re
import struct
import subprocess
from html.parser import HTMLParser


def parse_ssh_rsa_blob(encoded):
    try:
        blob = base64.b64decode(encoded, validate=True)
    except Exception as exc:
        raise AssertionError(f"The key field is not valid base64: {exc}")

    offset = 0

    def read_field(name):
        nonlocal offset
        assert offset + 4 <= len(blob), f"Truncated SSH RSA blob before {name}."
        length = struct.unpack(">I", blob[offset:offset + 4])[0]
        offset += 4
        assert offset + length <= len(blob), f"Truncated SSH RSA blob in {name}."
        value = blob[offset:offset + length]
        offset += length
        return value

    algorithm = read_field("algorithm")
    exponent_bytes = read_field("public exponent")
    modulus_bytes = read_field("modulus")

    assert offset == len(blob), "The SSH RSA blob contains trailing data."
    assert algorithm == b"ssh-rsa", "The base64 blob is not an SSH RSA key blob."
    assert exponent_bytes, "The SSH RSA public exponent is empty."
    assert modulus_bytes, "The SSH RSA modulus is empty."

    exponent = int.from_bytes(exponent_bytes, "big", signed=True)
    modulus = int.from_bytes(modulus_bytes, "big", signed=True)
    assert exponent > 1 and exponent % 2 == 1, "The SSH RSA public exponent is invalid."
    assert modulus > 1 and modulus % 2 == 1, "The SSH RSA modulus is invalid."


# Global browser event-handler attributes that can be dispatched on an element.
GLOBAL_EVENTS = {
    "animationcancel", "animationend", "animationiteration", "animationstart",
    "auxclick", "beforeinput", "beforetoggle", "blur", "cancel", "change",
    "click", "close", "contextmenu", "copy", "cut", "dblclick", "drag",
    "dragend", "dragenter", "dragleave", "dragover", "dragstart", "drop",
    "focus", "focusin", "focusout", "formdata", "input", "invalid",
    "keydown", "keypress", "keyup", "mousedown", "mouseenter", "mouseleave",
    "mousemove", "mouseout", "mouseover", "mouseup", "paste", "pointercancel",
    "pointerdown", "pointerenter", "pointerleave", "pointermove", "pointerout",
    "pointerover", "pointerup", "reset", "resize", "scroll", "select",
    "submit", "toggle", "touchcancel", "touchend", "touchmove", "touchstart",
    "transitioncancel", "transitionend", "transitionrun", "transitionstart", "wheel"
}
RESOURCE_ERROR_TAGS = {"audio", "img", "input", "object", "source", "track", "video"}


class BrowserFragment(HTMLParser):
    """Parse the comment as an HTML fragment and model dispatch of real DOM events."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.handlers = []

    def handle_starttag(self, tag, attrs):
        attr_map = dict(attrs)
        for name, value in attrs:
            if not name.startswith("on") or value is None:
                continue
            event = name[2:].lower()
            supported = event in GLOBAL_EVENTS
            if event == "error" and tag in RESOURCE_ERROR_TAGS:
                supported = True
            if tag in {"animate", "animatemotion", "animatetransform", "set"} and event in {"begin", "end", "repeat"}:
                supported = True
            if supported:
                self.handlers.append((tag, event, value, attr_map))

    handle_startendtag = handle_starttag


def handler_executes_pwned(handler):
    # Execute the direct alert call accepted by the challenge in a constrained
    # event-handler model. Full matching prevents dead-code or fabricated text
    # from being mistaken for execution.
    match = re.fullmatch(
        r"\s*(?:window\s*\.\s*)?alert\s*\(\s*(['\"])PWNED\1\s*\)\s*;?\s*",
        handler,
    )
    return match is not None


def test_generate_payload_c_exists():
    assert os.path.isfile("/home/user/generate_payload.c"), "The file /home/user/generate_payload.c does not exist."


def test_compile_and_execute_payload():
    # Compile
    compile_proc = subprocess.run(
        ["gcc", "-o", "/home/user/generate_payload", "/home/user/generate_payload.c"],
        capture_output=True,
        text=True
    )
    assert compile_proc.returncode == 0, f"Compilation failed:\n{compile_proc.stderr}"

    assert os.path.isfile("/home/user/generate_payload"), "Compiled executable not found."

    # Execute
    run_proc = subprocess.run(
        ["/home/user/generate_payload"],
        capture_output=True,
        text=True
    )
    assert run_proc.returncode == 0, "Execution of generate_payload failed (non-zero exit code)."

    output = run_proc.stdout.strip()
    assert output, "The program produced no output."

    # 1. Check for SSH key structure
    assert output.startswith("ssh-rsa AAAAB3NzaC1yc2E"), "Output does not start with 'ssh-rsa AAAAB3NzaC1yc2E'."

    parts = output.split(" ", 2)
    assert len(parts) == 3, "Output does not have three space-separated parts (type, key, comment)."

    key_part = parts[1]
    assert len(key_part) >= 64, "The base64 key part is less than 64 characters long."
    parse_ssh_rsa_blob(key_part)

    # 2. Check for evasion constraints (no 'script' or 'onload' case-insensitive)
    lower_output = output.lower()
    assert "script" not in lower_output, "The payload contains the banned string 'script'."
    assert "onload" not in lower_output, "The payload contains the banned string 'onload'."

    # 3. Check for valid XSS executing alert('PWNED')
    assert "alert('pwned')" in lower_output or "alert('PWNED')" in output, "The payload does not contain alert('PWNED')."

    # 4. Ensure an HTML event handler or similar vector is present (since onload and script are banned)
    assert re.search(r"on[a-z]+=", output, re.IGNORECASE), "The payload does not contain an HTML event handler (e.g., onerror=)."

    # Parse the comment in an HTML-fragment context. Only browser-supported
    # event attributes are dispatchable; names such as onfake are ignored.
    comment = parts[2]
    fragment = BrowserFragment()
    fragment.feed(comment)
    fragment.close()
    assert fragment.handlers, "The comment has no browser-supported HTML event handler."
    assert any(handler_executes_pwned(handler) for _, _, handler, _ in fragment.handlers), \
        "Dispatching the comment's browser-supported event handlers does not execute alert('PWNED')."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
