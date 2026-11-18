#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/alignment.fasta
>seq1
ACDEF
>seq2
ACDEF
>seq3
ACDQF
>seq4
AWDEF
>seq5
ACDEF
EOF

cat << 'EOF' > /home/user/target.fasta
>target_seq_1
ACDQQ
EOF

cat << 'EOF' > /home/user/calc_pwm.sh
#!/bin/bash
# Original buggy script calculating log2(prob/0.05) without pseudocounts
# This is a placeholder that fails with log(0)
awk '
BEGIN {
    split("A C D E F G H I K L M N P Q R S T V W Y", aa, " ")
    bg = 0.05
}
/^>/ { seq++; next }
{
    for(i=1; i<=length($0); i++) {
        c[i, substr($0,i,1)]++
        len = length($0)
    }
}
END {
    for(i=1; i<=len; i++) {
        printf "%d", i
        for(j=1; j<=20; j++) {
            prob = c[i, aa[j]] / seq
            if(prob == 0) val = "-inf"
            else val = log(prob/bg)/log(2)
            printf "\t%.3f", val
        }
        printf "\n"
    }
}
' "$1"
EOF

chmod +x /home/user/calc_pwm.sh
chmod -R 777 /home/user
