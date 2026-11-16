Slice assignment corner case
For example,
```sh
 % jq -n -c '[range(5)] | (.[2:0] = [999])'
[0,1,999,2,3,4]
 % java -jar jackson-jq-cli-1.0.0-preview.20191208.jar -n -c '[range(5)] | (.[2:0] = [999])'
[999,0,1,2,3,4]
```
