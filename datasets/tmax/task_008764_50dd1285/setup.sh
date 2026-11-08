#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_transcripts.csv
transcript_id,date,customer_email,cc_number,transcript_text
T001,12/31/2022,alice@example.com,1234-5678-9012-3456,Hello I need help with my account. Email me at alice@example.com!
T002,2023/01/15,bob.smith@work.net,9876543210987654,My card was charged twice.
T001,12/31/2022,alice@example.com,1234-5678-9012-3456,Hello I need help with my account. Email me at alice@example.com!
T003,15-02-2023,charlie@domain.org,1111-2222-3333-4444,Update my billing to charlie@domain.org please. THANKS.
T004,03/05/2023,dave@site.com,4444555566667777,Cancel my subscription.
EOF

    chmod -R 777 /home/user
