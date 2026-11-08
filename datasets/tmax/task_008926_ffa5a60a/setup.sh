#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/patients.csv
ID,Name,Email,SSN,Notes
1,Alice Smith,alice@example.com,123-45-6789,Healthy patient
2,Bob Jones,bob@work.org,987-65-4321,Patient has a
bad cough
3,Charlie Brown,chuck@peanuts.com,555-66-7777,Routine checkup
4,Diana Prince,diana@amazon.com,111-22-3333,
5,Eve Hacker,eve@malicious.net,999-00-1111,Requires followup
6,Frank,frank@broken.com,222-33-4444,Missing
data
7,Grace Hopper,grace@navy.mil,888-77-6666,Excellent health
EOF

    cat << 'EOF' > /home/user/.expected_report.json
{
  "dataset": "patients",
  "valid_count": 5,
  "data": [
    {
      "id": "1",
      "domain": "example.com",
      "ssn": "XXX-XX-6789"
    },
    {
      "id": "3",
      "domain": "peanuts.com",
      "ssn": "XXX-XX-7777"
    },
    {
      "id": "4",
      "domain": "amazon.com",
      "ssn": "XXX-XX-3333"
    },
    {
      "id": "5",
      "domain": "malicious.net",
      "ssn": "XXX-XX-1111"
    },
    {
      "id": "7",
      "domain": "navy.mil",
      "ssn": "XXX-XX-6666"
    }
  ]
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
