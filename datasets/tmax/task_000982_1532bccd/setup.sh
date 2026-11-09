#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user

    python3 -c "
import random
random.seed(42)
with open('/home/user/random_seed.dat', 'wb') as f:
    f.write(bytes([random.randint(0, 255) for _ in range(1048576)]))
"

    cat << 'EOF' > /home/user/stopwords.txt
the
and
this
that
was
for
with
are
but
not
you
all
any
EOF

    cat << 'EOF' > /home/user/reviews.csv
id,rating,text
1,5,The battery life is amazing and fantastic!
2,2,Terrible product. Battery drains fast.
3,4,Good value for money. Amazing battery!
4,1,Awful. Customer service is terrible and slow.
5,5,Fantastic product! I love the screen and battery.
6,3,It is okay. Nothing amazing but not terrible.
7,5,Highly recommended. Amazing screen quality.
8,1,Screen broke fast. Terrible!
9,4,Fast delivery. Good battery life.
10,5,Amazing! Battery is fantastic.
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
