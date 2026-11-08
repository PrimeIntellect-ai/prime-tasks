Division by empty string yields array with empty strings at start and end
```sh
❯ jq -c '. / ""' <<< '"abcde"'
["a","b","c","d","e"]

❯ xq -c '. / ""' <<< '"abcde"'
["","a","b","c","d","e",""]

❯ xq --version
xq 0.1.9-b5d6c8d747459413aadf8298237f1628edbbd9e7
```
