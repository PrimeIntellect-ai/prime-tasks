#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk
pip3 install pytest

useradd -m -s /bin/bash user || true
mkdir -p /home/user

# Generate reads.tsv
cat << 'EOF' > /home/user/reads.tsv
SampleA	R1	ATCGATCGATCGATCGATCG
SampleA	R2	ATCGATCGATCGATCGATCG
SampleA	R3	ATCGATCGATCGATCGATCG
SampleA	R4	ATCGATCGATCGATCGATCG
SampleA	R5	ATCGATCGATCGATCGATCG
SampleA	R6	ATCGATCGATCGATCGATCG
SampleA	R7	ATCGATCGATCGATCGATCG
SampleA	R8	ATCGATCGATCGATCGATCG
SampleA	R9	ATCGATCGATCGATCGATCG
SampleA	R10	ATCGATCGATCGATCGATCG
EOF

bash -c '
for i in {11..40}; do
  echo -e "SampleA\tR${i}\tATCGATCGATCGATCGATCGATCGA" >> /home/user/reads.tsv
done

for i in {41..60}; do
  echo -e "SampleB\tR${i}\tATCGATCGATCGATCGATCG" >> /home/user/reads.tsv
done

for i in {61..80}; do
  echo -e "SampleB\tR${i}\tATCGATCGATCGATCGATCGATCGA" >> /home/user/reads.tsv
done
'

# Generate reference.fasta
BIN1="ATATATATATATATATATATATATATATATGCGCGCGCGCGCGCGCGCGC"
BIN2="GCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCATATATATATATAT"
BIN3="GCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCGCATATATATAT"
BIN4="ATATATATATATATATATATATATATATATATATATATATGCGCGCGCGC"
LEFTOVER="ATGCATGCATGCATGCATGC"

cat << EOF > /home/user/reference.fasta
>chr1_reference_sequence
${BIN1}${BIN2}
${BIN3}
${BIN4}${LEFTOVER}
EOF

chmod -R 777 /home/user
