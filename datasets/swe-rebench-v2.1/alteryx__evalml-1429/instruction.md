Remove `core-requirements.txt` from installed package
https://github.com/alteryx/evalml/pull/1293 updated and fixed our CLI tool by adding `core-requirements.txt` to our package data so it is readable. However, users may be confused as to why this is being installed. We should look into how to achieve the same functionality without adding `core-requirements.txt` to our installed package.
