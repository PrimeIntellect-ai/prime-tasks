#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import shlex
import shutil
import string
import subprocess
import tempfile

LOG_FILTER_SCRIPT = "/home/user/log_filter.sh"
LOGROTATE_CONF = "/home/user/logrotate.conf"
EVIL_CORPUS_DIR = "/app/corpus/evil"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
BILLING_IMAGE = "/app/billing_rules.png"


def run_filter(path, direct=False):
    command = [LOG_FILTER_SCRIPT, path] if direct else ["bash", LOG_FILTER_SCRIPT, path]
    return subprocess.run(command, capture_output=True, timeout=5).returncode


def test_log_filter_script_exists_and_executable():
    assert os.path.isfile(LOG_FILTER_SCRIPT), f"Missing script: {LOG_FILTER_SCRIPT}"
    assert os.access(LOG_FILTER_SCRIPT, os.X_OK), f"Script is not executable: {LOG_FILTER_SCRIPT}"


def _tokens(line):
    lexer = shlex.shlex(line, posix=True, punctuation_chars="{}")
    lexer.whitespace_split = True
    lexer.commenters = "#"
    return list(lexer)


def _validate_directive(tokens):
    assert tokens, "Empty directive"
    name, args = tokens[0], tokens[1:]

    no_arg = {
        "hourly", "daily", "weekly", "monthly", "yearly",
        "compress", "nocompress", "delaycompress", "nodelaycompress",
        "missingok", "nomissingok", "ifempty", "notifempty",
        "copy", "nocopy", "copytruncate", "nocopytruncate",
        "renamecopy", "norenamecopy", "dateext", "nodateext",
        "dateyesterday", "datehourago", "sharedscripts", "nosharedscripts",
        "mailfirst", "maillast", "nomail", "nocreate", "noolddir",
        "shred", "noshred", "nocreateolddir"
    }
    one_arg = {
        "size", "minsize", "maxsize", "start", "maxage", "minage",
        "olddir", "mail", "extension", "addextension", "dateformat",
        "compresscmd", "uncompresscmd", "compressext", "shredcycles",
        "include"
    }
    variable_arg = {"create", "createolddir", "su", "compressoptions", "tabooext"}

    if name in no_arg:
        assert not args, f"Directive {name} takes no arguments"
    elif name == "rotate":
        assert len(args) == 1 and re.fullmatch(r"-?\d+", args[0]), "Invalid rotate directive"
    elif name in one_arg:
        assert len(args) == 1, f"Directive {name} requires one argument"
    elif name in variable_arg:
        assert args, f"Directive {name} requires arguments"
    else:
        raise AssertionError(f"Unknown or misplaced logrotate directive: {name}")


def _apply_semantics(state, tokens):
    name = tokens[0]
    if name in {"hourly", "daily", "weekly", "monthly", "yearly"}:
        state["frequency"] = name
    elif name in {"compress", "nocompress"}:
        state["compress"] = name == "compress"
    elif name in {"missingok", "nomissingok"}:
        state["missingok"] = name == "missingok"
    elif name == "rotate":
        state["rotate"] = int(tokens[1])


def _parse_logrotate(path):
    with open(path, "r", encoding="utf-8") as handle:
        lines = handle.readlines()

    global_state = {}
    target_states = []
    in_block = False
    in_script = False
    block_patterns = []
    block_state = None
    script_starters = {"prerotate", "postrotate", "firstaction", "lastaction"}

    for line_number, raw in enumerate(lines, 1):
        stripped = raw.strip()
        if in_script:
            if stripped == "endscript":
                in_script = False
            continue

        tokens = _tokens(raw)
        if not tokens:
            continue

        if not in_block:
            if tokens[-1:] == ["{"]:
                assert len(tokens) >= 2, f"Missing log pattern on line {line_number}"
                assert "}" not in tokens[:-1] and "{" not in tokens[:-1], f"Invalid block header on line {line_number}"
                block_patterns = tokens[:-1]
                block_state = dict(global_state)
                in_block = True
            else:
                assert "{" not in tokens and "}" not in tokens, f"Unexpected brace on line {line_number}"
                _validate_directive(tokens)
                _apply_semantics(global_state, tokens)
        else:
            if tokens == ["}"]:
                if "/home/user/logs/*.log" in block_patterns:
                    target_states.append(block_state)
                in_block = False
                block_patterns = []
                block_state = None
            elif tokens[0] in script_starters:
                assert len(tokens) == 1, f"Invalid script directive on line {line_number}"
                in_script = True
            else:
                assert "{" not in tokens and "}" not in tokens, f"Unexpected brace on line {line_number}"
                _validate_directive(tokens)
                _apply_semantics(block_state, tokens)

    assert not in_script, "Unterminated logrotate script section"
    assert not in_block, "Unterminated logrotate block"
    assert len(target_states) == 1, "Configuration must contain exactly one block applying to /home/user/logs/*.log"
    return target_states[0]


def test_logrotate_conf():
    assert os.path.isfile(LOGROTATE_CONF), f"Missing logrotate config: {LOGROTATE_CONF}"

    with open(LOGROTATE_CONF, "r") as f:
        content = f.read()

    # Preserve the original required-directive assertions.
    assert "/home/user/logs/*.log" in content, "Missing target log files pattern in logrotate.conf"
    assert "daily" in content, "Missing 'daily' directive in logrotate.conf"
    assert "rotate 7" in content, "Missing 'rotate 7' directive in logrotate.conf"
    assert "compress" in content, "Missing 'compress' directive in logrotate.conf"
    assert "missingok" in content, "Missing 'missingok' directive in logrotate.conf"

    state = _parse_logrotate(LOGROTATE_CONF)
    assert state.get("frequency") == "daily", "Target block is not configured for daily rotation"
    assert state.get("rotate") == 7, "Target block does not keep exactly 7 rotations"
    assert state.get("compress") is True, "Compression is not enabled for the target block"
    assert state.get("missingok") is True, "missingok is not enabled for the target block"

    # When the real parser is available, also require it to accept the configuration.
    logrotate = shutil.which("logrotate")
    if logrotate:
        with tempfile.TemporaryDirectory() as temp_dir:
            state_file = os.path.join(temp_dir, "state")
            result = subprocess.run(
                [logrotate, "--debug", "--state", state_file, LOGROTATE_CONF],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, f"logrotate rejected configuration: {result.stderr or result.stdout}"


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS_DIR), f"Missing evil corpus directory: {EVIL_CORPUS_DIR}"
    assert os.path.isdir(CLEAN_CORPUS_DIR), f"Missing clean corpus directory: {CLEAN_CORPUS_DIR}"

    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]

    evil_bypassed = []
    clean_modified = []

    for file_path in evil_files:
        if run_filter(file_path) != 1:
            evil_bypassed.append(os.path.basename(file_path))

    for file_path in clean_files:
        if run_filter(file_path) != 0:
            clean_modified.append(os.path.basename(file_path))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")

    assert not error_messages, " | ".join(error_messages)


def _random_text():
    alphabet = string.ascii_letters + string.digits + " _-:./"
    return "".join(secrets.choice(alphabet) for _ in range(random.randint(20, 90)))


def test_randomized_classifier_behavior_and_path_independence():
    ocr = subprocess.run(
        ["tesseract", BILLING_IMAGE, "stdout"],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    ).stdout
    match = re.search(r"EXEMPT_PROJECT:\s*([A-Za-z0-9_.-]+)", ocr)
    assert match, "Could not extract exempt project from billing image"
    exemption = f"EXEMPT_PROJECT: {match.group(1)}"

    cases = []
    for _ in range(8):
        noise = _random_text()
        cases.extend([
            (".log", noise + "\n[DEBUG]\n" + _random_text(), 1),
            (".log", noise + "\n[INFO]\n" + _random_text(), 0),
            (secrets.choice([".txt", ".data", ".LOG", ".log.bak"]), noise + "[DEBUG]" + _random_text(), 0),
            (".log", noise + "[DEBUG]" + _random_text() + "[ERROR]", 0),
            (".log", noise + "[DEBUG]" + _random_text() + exemption, 0),
            (".log", noise + "DEBUG" + _random_text() + "[ DEBUG ]", 0),
        ])
    random.SystemRandom().shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="classifier-" + secrets.token_hex(5) + "-") as root:
        for index, (suffix, contents, expected) in enumerate(cases):
            directory = os.path.join(root, secrets.token_hex(6))
            os.makedirs(directory)
            spacer = " with space" if index % 5 == 0 else ""
            path = os.path.join(directory, secrets.token_hex(8) + spacer + suffix)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(contents)
            actual = run_filter(path, direct=True)
            assert actual == expected, f"Wrong exit code for randomized case {index}: expected {expected}, got {actual}"

        # Identical deletable content must not change classification based on directory names.
        debug_content = _random_text() + "\n[DEBUG]\n" + _random_text()
        for label in ("clean-" + secrets.token_hex(4), "evil-" + secrets.token_hex(4)):
            directory = os.path.join(root, label)
            os.makedirs(directory)
            path = os.path.join(directory, secrets.token_hex(8) + ".log")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(debug_content)
            assert run_filter(path, direct=True) == 1
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
