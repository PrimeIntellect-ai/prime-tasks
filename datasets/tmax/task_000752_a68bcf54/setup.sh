#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk sed grep coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/reviews.csv
id,rating,review_text
1,5,"The product is great and the quality is excellent!"
2,3,"Average quality, but the price is right in my budget."
3,1,"Terrible! I hate it and it is a waste of money."
4,4,"Great price, excellent quality. Would buy again."
5,2,"Not great. Quality could be better, and price is too high."
EOF

    cat << 'EOF' > /home/user/stopwords.txt
the
a
is
in
and
to
it
of
my
be
too
but
i
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
