Modify operator on overlapping paths
I noticed that `xq` is incompatible on the query with modify operator (`|=`) with overlapping paths.
```sh
 $ xq --version
xq 0.2.39-ccae20f320d451effd67014434fb13b2fc3a58b0

 $ xq -n '{foo:0} | (.foo,.foo,.foo) |= .+1'
{
  "foo": 1
}

 $ jq -n '{foo:0} | (.foo,.foo,.foo) |= .+1'
{
  "foo": 3
}
```
