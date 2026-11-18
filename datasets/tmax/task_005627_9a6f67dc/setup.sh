#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk coreutils findutils
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/raw_feedback.jsonl
{"id": 1, "category": "app_review", "comment": "Great app! No bugs so far."}
{"id": 2, "category": "app_review", "comment": "Fix the crash on startup \uG123 please."}
{"id": 3, "category": "support_ticket", "comment": "I cannot login, email me at admin@domain.com"}
{"id": 4, "category": "app_review", "comment": "Contact the dev at super_dev.123@my-startup.co.uk! Also \u0041 is A, but \uZZZZ is broken."}
{"id": 5, "category": "app_review", "comment": "Valid unicode \u2764 email: plain@mail.com"}
{"id": 6, "category": "app_review", "comment": "Broken JSON structure without closing brace
{"id": 7, "category": "app_review", "comment": "Just another \u123X test."}
EOF

    cat << 'EOF' > /home/user/.expected_feedback.jsonl
{"id":1,"category":"app_review","comment":"Great app! No bugs so far."}
{"id":2,"category":"app_review","comment":"Fix the crash on startup [BAD_UNICODE] please."}
{"id":4,"category":"app_review","comment":"Contact the dev at [REDACTED_EMAIL]! Also \u0041 is A, but [BAD_UNICODE] is broken."}
{"id":5,"category":"app_review","comment":"Valid unicode \u2764 email: [REDACTED_EMAIL]"}
{"id":7,"category":"app_review","comment":"Just another [BAD_UNICODE] test."}
EOF

    cat << 'EOF' > /tmp/verify.sh
#!/bin/bash
if [ ! -f /home/user/clean_feedback.jsonl ]; then
    echo "Output file missing"
    exit 1
fi

# Compare canonicalized JSON representations to ignore key ordering and whitespace differences
jq -c '.' /home/user/clean_feedback.jsonl | sort > /tmp/actual_sorted.jsonl
jq -c '.' /home/user/.expected_feedback.jsonl | sort > /tmp/expected_sorted.jsonl

if ! cmp -s /tmp/actual_sorted.jsonl /tmp/expected_sorted.jsonl; then
    echo "Output dataset does not match expectations."
    diff /tmp/expected_sorted.jsonl /tmp/actual_sorted.jsonl
    exit 1
fi

if ! grep -q "split\|xargs -P\|&" /home/user/clean_pipeline.sh; then
    echo "Parallelism tools not found in script."
    exit 1
fi

echo "Success"
exit 0
EOF
    chmod +x /tmp/verify.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
