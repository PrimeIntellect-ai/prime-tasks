#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/derivations.tsv
Source	Target	Relation
DS1	DS2	DERIVED_FROM
DS2	DS3	DERIVED_FROM
DS3	DS1	DERIVED_FROM
DS4	DS5	DERIVED_FROM
DS5	DS6	DERIVED_FROM
DS6	DS4	DERIVED_FROM
DS1	DS4	CITES
DS7	DS8	DERIVED_FROM
DS8	DS9	DERIVED_FROM
DS9	DS7	CITES
DS10	DS11	DERIVED_FROM
DS11	DS10	DERIVED_FROM
EOF

    cat << 'EOF' > /home/user/metadata.tsv
DatasetID	ResearcherName	CreationYear
DS1	Alice	2020
DS2	Bob	2021
DS3	Alice	2022
DS4	Charlie	2019
DS5	Dave	2020
DS6	Eve	2021
DS7	Frank	2020
DS8	Grace	2021
DS9	Heidi	2022
DS10	Ivan	2020
DS11	Judy	2021
EOF

    chmod -R 777 /home/user
