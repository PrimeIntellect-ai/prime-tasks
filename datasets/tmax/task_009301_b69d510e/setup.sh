#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/docs_raw
cd /home/user/docs_raw

# Generate 50 files: 20 FINAL, 30 DRAFT using seq to avoid bash brace expansion issues in /bin/sh
for i in $(seq 1 50); do
  if [ $((i % 5)) -eq 0 ] || [ $((i % 5)) -eq 2 ]; then
    # FINAL files (20 total)
    cat <<EOF > doc_${i}.txt
STATUS: FINAL
Date: 2023-10-0${i}
[HEADER] Introduction Section ${i}
This is the final text for document ${i}.
[HEADER] Conclusion
End of document.
EOF
  else
    # DRAFT files (30 total)
    cat <<EOF > doc_${i}.txt
STATUS: DRAFT
Date: 2023-10-0${i}
[HEADER] Draft Section ${i}
This is draft text. Needs revision.
EOF
  fi
done

chmod -R 777 /home/user
