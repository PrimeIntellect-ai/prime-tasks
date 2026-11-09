#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

csv_content = """ReviewID,Timestamp,UserID,ProductID,Rating,ReviewText
1,2023-10-01T10:00:00,U001,PROD_A,5,Great product!
2,2023-10-01T10:05:00,U001,PROD_A,4,Great product!
3,2023-10-02T11:00:00,U002,PROD_A,4,Good value.
4,2023-10-01T09:00:00,U003,PROD_B,2,Did not like it.
5,2023-10-01T08:50:00,U003,PROD_B,2,Did not like it.
6,2023-10-03T14:00:00,U004,PROD_B,1,Terrible.
7,2023-10-04T16:00:00,U005,PROD_B,3,Okay I guess.
8,2023-10-05T08:00:00,U006,PROD_C,5,Perfect!
9,2023-10-05T08:00:01,U006,PROD_C,5,Perfect!
"""

os.makedirs("/home/user", exist_ok=True)

with open("/home/user/reviews.csv", "w") as f:
    f.write(csv_content)

L = chr(123) * 2
R = chr(125) * 2
template_content = f"## Product: {L}ProductID{R}\n- Total Reviews: {L}TotalReviews{R}\n- Average Rating: {L}AverageRating{R}"

with open("/home/user/template.md", "w") as f:
    f.write(template_content)
'

    chmod -R 777 /home/user
