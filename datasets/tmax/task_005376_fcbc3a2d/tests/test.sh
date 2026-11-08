#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

PING_PATH="$(command -v ping)"
PING_BACKUP="$(mktemp /tmp/original-ping.XXXXXX)"
cp -a "$PING_PATH" "$PING_BACKUP"
restore_ping() {
    cp -a "$PING_BACKUP" "$PING_PATH" 2>/dev/null || true
    rm -f "$PING_BACKUP"
}
trap restore_ping EXIT

TOKEN="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
export VERIFIER_GOOD_DOMAIN="good-${TOKEN}.example.test"
export VERIFIER_BAD_DOMAIN="bad-${TOKEN}.example.test"
export VERIFIER_PING_LOG="/tmp/verifier-ping-${TOKEN}.log"
: > "$VERIFIER_PING_LOG"

cat > "$PING_PATH" <<'PING_EOF'
#!/bin/bash
{
    printf '%s\t' "$@"
    printf '\n'
} >> "$VERIFIER_PING_LOG"

for arg in "$@"; do
    if [ "$arg" = "$VERIFIER_BAD_DOMAIN" ]; then
        exit 1
    fi
done
exit 0
PING_EOF
chmod 755 "$PING_PATH"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess


def test_script_exists():
    """Test that the bash script was created."""
    script_path = "/home/user/check_ingress.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_good_manifest_remains():
    """Test that the good manifest remains in the manifests directory."""
    good_yaml = "/home/user/k8s-operator/manifests/app-good.yaml"
    assert os.path.isfile(good_yaml), f"File {good_yaml} should still exist in the manifests directory."


def test_bad_manifest_moved():
    """Test that the bad manifest was moved to the quarantine directory."""
    bad_yaml_orig = "/home/user/k8s-operator/manifests/app-bad.yaml"
    bad_yaml_quarantine = "/home/user/k8s-operator/quarantine/app-bad.yaml"

    assert not os.path.isfile(bad_yaml_orig), f"File {bad_yaml_orig} should have been moved out of the manifests directory."
    assert os.path.isfile(bad_yaml_quarantine), f"File {bad_yaml_quarantine} should exist in the quarantine directory."


def test_dns_failures_log():
    """Test that the bad domain was logged to dns_failures.log."""
    log_file = "/home/user/k8s-operator/alerts/dns_failures.log"
    assert os.path.isfile(log_file), f"Log file {log_file} was not created."

    with open(log_file, 'r') as f:
        content = f.read().strip().split('\n')

    assert "definitely.invalid.domain.local.999" in content, f"Expected domain not found in {log_file}."


def test_mail_config_updated():
    """Test that the mail config file was updated with ALERT_TRIGGERED=1."""
    mail_config = "/home/user/k8s-operator/mail_config.rc"
    assert os.path.isfile(mail_config), f"File {mail_config} is missing."

    with open(mail_config, 'r') as f:
        content = f.read()

    assert "ALERT_TRIGGERED=1" in content, f"Expected 'ALERT_TRIGGERED=1' to be appended to {mail_config}."


def _valid_ping_arguments(args, domain):
    counts = []
    timeouts = []
    domains = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == "-c":
            assert i + 1 < len(args), "ping -c is missing its value"
            counts.append(args[i + 1])
            i += 2
        elif re.fullmatch(r"-c.+", arg):
            counts.append(arg[2:])
            i += 1
        elif arg == "-W":
            assert i + 1 < len(args), "ping -W is missing its value"
            timeouts.append(args[i + 1])
            i += 2
        elif re.fullmatch(r"-W.+", arg):
            timeouts.append(arg[2:])
            i += 1
        elif arg == domain:
            domains.append(arg)
            i += 1
        else:
            return False
    return counts == ["1"] and timeouts == ["1"] and domains == [domain]


def test_script_processes_fresh_manifests_using_ping():
    base = "/home/user/k8s-operator"
    manifests = os.path.join(base, "manifests")
    quarantine = os.path.join(base, "quarantine")
    alerts = os.path.join(base, "alerts", "dns_failures.log")
    mail_config = os.path.join(base, "mail_config.rc")
    good_domain = os.environ["VERIFIER_GOOD_DOMAIN"]
    bad_domain = os.environ["VERIFIER_BAD_DOMAIN"]
    ping_log = os.environ["VERIFIER_PING_LOG"]

    good_name = "verifier-good.yaml"
    bad_name = "verifier-bad.yaml"
    good_path = os.path.join(manifests, good_name)
    bad_path = os.path.join(manifests, bad_name)
    good_quarantine = os.path.join(quarantine, good_name)
    bad_quarantine = os.path.join(quarantine, bad_name)

    for path in (good_path, bad_path, good_quarantine, bad_quarantine):
        if os.path.exists(path):
            os.remove(path)

    manifest_template = "apiVersion: networking.k8s.io/v1\nkind: Ingress\nspec:\n  host: {}\n"
    with open(good_path, "w") as f:
        f.write(manifest_template.format(good_domain))
    with open(bad_path, "w") as f:
        f.write(manifest_template.format(bad_domain))
    with open(mail_config, "w") as f:
        f.write("ALERT_TRIGGERED=0\n")
    open(ping_log, "w").close()

    result = subprocess.run(
        ["/bin/bash", "/home/user/check_ingress.sh"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )

    assert os.path.isfile(good_path), "A manifest whose ping succeeds must remain in manifests."
    assert not os.path.exists(good_quarantine), "A successful manifest must not be quarantined."
    assert not os.path.exists(bad_path), "A manifest whose ping fails must leave manifests."
    assert os.path.isfile(bad_quarantine), "A manifest whose ping fails must be moved to quarantine."

    assert os.path.isfile(alerts), "The DNS failure log was not created."
    with open(alerts) as f:
        alert_lines = f.read().splitlines()
    assert bad_domain in alert_lines, "The freshly generated failing domain was not logged as its own line."

    with open(mail_config) as f:
        mail_lines = f.read().splitlines()
    assert "ALERT_TRIGGERED=1" in mail_lines, "The fresh failure did not trigger the mail configuration."

    with open(ping_log) as f:
        calls = [[part for part in line.rstrip("\n").split("\t") if part] for line in f]

    for domain in (good_domain, bad_domain):
        domain_calls = [call for call in calls if domain in call]
        assert len(domain_calls) == 1, f"Expected exactly one ping invocation for {domain}, got {domain_calls!r}."
        assert _valid_ping_arguments(domain_calls[0], domain), (
            f"ping for {domain} must use exactly one packet (-c 1) and a one-second timeout (-W 1); "
            f"got {domain_calls[0]!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
