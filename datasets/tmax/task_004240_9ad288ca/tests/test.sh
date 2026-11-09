#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess


def generate_random_string(min_len, max_len, chars):
    length = random.randint(min_len, max_len)
    return ''.join(random.choice(chars) for _ in range(length))


def test_fuzz_equivalence_migrator():
    oracle_path = "/app/legacy_router_configurator"
    agent_script = "/home/user/migrator.py"

    assert os.path.exists(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)

    chars_tz = string.ascii_letters + string.digits + '/'
    chars_loc = string.ascii_letters + string.digits + '.' + '-'
    chars_int = string.digits
    chars_reg = string.ascii_letters + string.digits + '-'

    for i in range(100):
        arg1 = generate_random_string(3, 20, chars_tz)
        arg2 = generate_random_string(5, 15, chars_loc)
        arg3 = generate_random_string(5, 12, chars_int)
        arg4 = generate_random_string(5, 15, chars_reg)
        args = [arg1, arg2, arg3, arg4]

        oracle_res = subprocess.run([oracle_path] + args, capture_output=True, text=True)
        agent_res = subprocess.run(["python3", agent_script] + args, capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed on input {args}"
        assert agent_res.returncode == 0, f"Agent script failed on input {args}. Error: {agent_res.stderr}"
        assert oracle_res.stdout.strip() == agent_res.stdout.strip(), (
            f"Output mismatch on input {args}.\n"
            f"Oracle output: {oracle_res.stdout.strip()}\n"
            f"Agent output: {agent_res.stdout.strip()}"
        )


def test_generate_tag_script():
    script_path = "/home/user/generate_tag.sh"
    oracle_path = "/app/legacy_router_configurator"
    timezone_path = "/etc/timezone"
    locale_path = "/etc/default/locale"

    assert os.path.exists(script_path), f"Script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable"

    with open(script_path, 'r') as f:
        content = f.read()

    assert 'df' in content, "Script does not contain 'df'"
    assert '/etc/timezone' in content, "Script does not contain '/etc/timezone'"
    assert '/etc/default/locale' in content, "Script does not contain '/etc/default/locale'"
    assert '/home/user/migrator.py' in content, "Script does not contain '/home/user/migrator.py'"

    with open(timezone_path, 'rb') as f:
        original_timezone = f.read()
    with open(locale_path, 'rb') as f:
        original_locale = f.read()

    cases = [
        ("Pacific/Auckland", "fr_FR.UTF-8"),
        ("America/Los_Angeles", "de_DE.UTF-8"),
    ]

    try:
        for timezone, locale in cases:
            with open(timezone_path, 'w') as f:
                f.write(timezone + "\n")
            with open(locale_path, 'w') as f:
                f.write("LANG=" + locale + "\n")

            df_res = subprocess.run(["df", "-P", "-k", "/"], capture_output=True, text=True, check=True)
            df_lines = [line for line in df_res.stdout.splitlines() if line.strip()]
            assert len(df_lines) >= 2, "Could not parse df output"
            root_size = df_lines[-1].split()[1]

            expected = subprocess.run(
                [oracle_path, timezone, locale, root_size, "eu-west-2"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout
            actual = subprocess.run(
                [script_path],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=10,
            )

            assert actual.returncode == 0, (
                f"generate_tag.sh failed for timezone={timezone}, locale={locale}: {actual.stderr}"
            )
            assert actual.stdout == expected, (
                "generate_tag.sh did not dynamically extract and pass the required values.\n"
                f"Expected: {expected!r}\nActual: {actual.stdout!r}"
            )
    finally:
        with open(timezone_path, 'wb') as f:
            f.write(original_timezone)
        with open(locale_path, 'wb') as f:
            f.write(original_locale)


def parse_unit_file(content):
    sections = {}
    current = None
    for line_number, raw_line in enumerate(content.splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith('#') or line.startswith(';'):
            continue
        if line.startswith('[') and line.endswith(']'):
            current = line[1:-1]
            assert current, f"Empty section name on line {line_number}"
            sections.setdefault(current, {})
            continue
        assert current is not None, f"Directive outside a section on line {line_number}"
        assert '=' in line, f"Malformed directive on line {line_number}: {raw_line!r}"
        key, value = line.split('=', 1)
        key = key.strip()
        value = value.strip()
        assert key, f"Empty directive name on line {line_number}"
        sections[current].setdefault(key, []).append(value)
    return sections


def test_routing_tag_service():
    service_path = "/home/user/routing-tag.service"
    assert os.path.exists(service_path), f"Service file missing at {service_path}"

    with open(service_path, 'r') as f:
        content = f.read()

    # Preserve the original assertions.
    assert '[Unit]' in content, "Service file missing [Unit] section"
    assert '[Service]' in content, "Service file missing [Service] section"
    assert 'Type=oneshot' in content, "Service file missing Type=oneshot"
    assert 'ExecStart=/home/user/generate_tag.sh' in content, "Service file missing ExecStart=/home/user/generate_tag.sh"

    sections = parse_unit_file(content)
    assert 'Unit' in sections, "Service file missing a valid [Unit] section"
    assert 'Service' in sections, "Service file missing a valid [Service] section"
    assert 'Install' in sections, "Service file missing a valid [Install] section"

    descriptions = sections['Unit'].get('Description', [])
    assert any(value for value in descriptions), "[Unit] must contain a non-empty Description"
    assert 'oneshot' in sections['Service'].get('Type', []), "Type=oneshot must be in [Service]"
    assert '/home/user/generate_tag.sh' in sections['Service'].get('ExecStart', []), (
        "ExecStart=/home/user/generate_tag.sh must be in [Service]"
    )

    wanted_by = sections['Install'].get('WantedBy', [])
    targets = [target for value in wanted_by for target in value.split()]
    assert 'multi-user.target' in targets, (
        "[Install] must contain WantedBy=multi-user.target"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
