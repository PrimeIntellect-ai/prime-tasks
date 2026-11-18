#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas duckdb

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/institutions.csv
institution_id,name,country
1,Tech University,USA
2,Global Institute,UK
3,Data Academy,Canada
4,Science Center,USA
EOF

    cat << 'EOF' > /home/user/data/researchers.csv
id,name,institution_id,interest
101,Alice Smith,1,Machine Learning
102,Bob Jones,2,Data Science
103,Charlie Brown,1,Data Science
104,Diana Prince,3,AI
105,Evan Wright,4,Data Science
106,Fiona Gallagher,2,Robotics
EOF

    cat << 'EOF' > /home/user/data/publications.csv
paper_id,title,year
201,Deep Learning Advances,2019
202,Data Structures in Python,2020
203,AI for Good,2021
204,Graph Theory Applications,2018
205,Modern Data Science,2022
EOF

    cat << 'EOF' > /home/user/data/authorships.csv
paper_id,researcher_id
201,101
201,102
202,102
202,103
203,104
203,105
204,101
204,106
205,103
205,106
205,105
EOF

    cat << 'EOF' > /home/user/expected_collabs.csv
researcher_1,researcher_2,paper_title,inst_1,inst_2
Bob Jones,Charlie Brown,Data Structures in Python,Global Institute,Tech University
Charlie Brown,Evan Wright,Modern Data Science,Tech University,Science Center
Charlie Brown,Fiona Gallagher,Modern Data Science,Tech University,Global Institute
Diana Prince,Evan Wright,AI for Good,Data Academy,Science Center
Evan Wright,Fiona Gallagher,Modern Data Science,Science Center,Global Institute
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
