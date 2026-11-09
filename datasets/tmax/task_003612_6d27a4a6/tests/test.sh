#!/bin/bash
mkdir -p /logs/verifier
reward=0
BWRAP_PATH=""
BWRAP_BACKUP=""
CERT_BACKUP="/tmp/intermediate.pem.verifier-backup"

cleanup() {
    if [ -n "$CERT_BACKUP" ] && [ -f "$CERT_BACKUP" ]; then
        cp -f "$CERT_BACKUP" /app/certs/intermediate.pem >/dev/null 2>&1 || true
        rm -f "$CERT_BACKUP"
    fi
    if [ -n "$BWRAP_PATH" ] && [ -n "$BWRAP_BACKUP" ] && [ -e "$BWRAP_BACKUP" ]; then
        rm -f "$BWRAP_PATH"
        mv -f "$BWRAP_BACKUP" "$BWRAP_PATH" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

run_checks() {
    [ -f /home/user/auditor.go ] || return 1
    command -v go >/dev/null 2>&1 || return 1
    command -v bwrap >/dev/null 2>&1 || return 1

    go build -o /tmp/auditor-verifier /home/user/auditor.go || return 1
    [ -x /tmp/auditor-verifier ] || return 1

    BWRAP_PATH="$(command -v bwrap)"
    BWRAP_BACKUP="${BWRAP_PATH}.verifier-real"
    rm -f "$BWRAP_BACKUP"
    mv "$BWRAP_PATH" "$BWRAP_BACKUP" || return 1

    cat > "$BWRAP_PATH" <<'WRAPPER_EOF'
#!/bin/bash
printf '%s\n' "$@" >> /tmp/verifier_bwrap_args.txt
payload=/tmp/verifier_transcript_input.txt
[ -f "$payload" ] || exit 91
cat "$payload" > /home/user/voip_intercept.txt
cat "$payload" > /home/user/voip_intercept.wav.txt
cat "$payload" > /home/user/transcript.txt
cat "$payload" > /home/user/transcription.txt
for arg in "$@"; do
    case "$arg" in
        *.txt)
            if [ "$arg" != "/home/user/final_report.txt" ]; then
                mkdir -p "$(dirname "$arg")" 2>/dev/null || true
                cat "$payload" > "$arg" 2>/dev/null || true
            fi
            ;;
    esac
done
cat "$payload"
exit 0
WRAPPER_EOF
    chmod 755 "$BWRAP_PATH" || return 1

    python3 - <<'PY' || return 1
import json, random
ip = ".".join(str(random.randint(1, 223)) for _ in range(4))
dash = "4111-1111-1111-1111"
continuous = "4012888888881881"
spaces = "5555 5555 5555 4444"
text = (
    f"The backup server is at {ip} and the billing account uses the card {dash} for processing. "
    f"Secondary cards {continuous} and {spaces}; invalid address 999.999.999.999 remains."
)
expected = text.replace(ip, "[REDACTED]").replace(dash, "[REDACTED]")
expected = expected.replace(continuous, "[REDACTED]").replace(spaces, "[REDACTED]")
with open("/tmp/verifier_transcript_input.txt", "w") as f:
    f.write(text)
with open("/tmp/verifier_expected.json", "w") as f:
    json.dump({"expected": expected}, f)
PY

    cp /app/certs/intermediate.pem "$CERT_BACKUP" || return 1
    cp /app/certs/root.pem /app/certs/intermediate.pem || return 1
    : > /tmp/verifier_bwrap_args.txt
    rm -f /home/user/final_report.txt /home/user/voip_intercept.txt \
          /home/user/voip_intercept.wav.txt /home/user/transcript.txt \
          /home/user/transcription.txt

    timeout 30s /tmp/auditor-verifier >/tmp/verifier-invalid.out 2>&1
    invalid_rc=$?
    if [ "$invalid_rc" -eq 0 ] || [ "$invalid_rc" -eq 124 ]; then
        return 1
    fi
    [ ! -s /tmp/verifier_bwrap_args.txt ] || return 1

    cp "$CERT_BACKUP" /app/certs/intermediate.pem || return 1
    : > /tmp/verifier_bwrap_args.txt
    rm -f /home/user/final_report.txt /home/user/voip_intercept.txt \
          /home/user/voip_intercept.wav.txt /home/user/transcript.txt \
          /home/user/transcription.txt

    timeout 60s /tmp/auditor-verifier >/tmp/verifier-valid.out 2>&1 || return 1
    [ -s /tmp/verifier_bwrap_args.txt ] || return 1

    cat > /tmp/test_final_state.py <<'TEST_EOF'
import json
import os


def compute_accuracy(ref, hyp):
    ref_words = ref.lower().split()
    hyp_words = hyp.lower().split()
    redacted_count = hyp.count("[REDACTED]")
    if redacted_count < 2:
        return 0.0
    overlap = len(set(ref_words) & set(hyp_words))
    if len(set(ref_words)) == 0:
        return 0.0
    return overlap / float(len(set(ref_words)))


def adjacent(args, values):
    n = len(values)
    return any(args[i:i+n] == values for i in range(len(args) - n + 1))


def test_program_behavior_and_sandbox():
    report_path = "/home/user/final_report.txt"
    assert os.path.isfile(report_path), f"Final report is missing at {report_path}"
    with open(report_path) as f:
        output = f.read()
    with open("/tmp/verifier_expected.json") as f:
        expected_dynamic = json.load(f)["expected"]
    assert output == expected_dynamic, "Transcript was not preserved and redacted exactly"

    with open("/tmp/verifier_bwrap_args.txt") as f:
        args = [line.rstrip("\n") for line in f]
    assert "--unshare-net" in args
    assert adjacent(args, ["--ro-bind", "/", "/"])
    assert adjacent(args, ["--proc", "/proc"])
    assert adjacent(args, ["--tmpfs", "/tmp"])
    assert adjacent(args, ["--bind", "/home/user", "/home/user"])
    assert adjacent(args, ["--dev", "/dev"]) or adjacent(args, ["--dev-bind", "/dev", "/dev"])
    assert "/app/voip_intercept.wav" in args


def test_final_report_accuracy():
    report_path = "/home/user/final_report.txt"
    assert os.path.isfile(report_path), f"Final report is missing at {report_path}"
    with open(report_path, "r") as f:
        output = f.read()
    expected = "The backup server is at [REDACTED] and the billing account uses the card [REDACTED] for processing."
    score = compute_accuracy(expected, output)
    assert score >= 0.85, f"Accuracy score {score:.2f} is below the threshold of 0.85. Output was: {output}"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
    return 0
}

if run_checks; then
    reward=1
fi
cleanup
trap - EXIT
echo "$reward" > /logs/verifier/reward.txt
