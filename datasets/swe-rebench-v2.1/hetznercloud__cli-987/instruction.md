fix: some flags use StringArray which does not split by comma
### TL;DR

Some commands do not allow comma separated input for list flags. Example `hcloud firewall add-rule --destionation-ips`

### Expected behavior

Our flags should consistently allow the use of commas to specify multiple values.

### Observed behavior

If a comma is used to separate the values, CLI does not split them and instead passes it along as one big value. It is not clear for the user how they can circumvent this.

### Minimal working example

```shell
$ hcloud firewall create test
$ hcloud firewall add-rule \
    --direction in \
    --port 443 \
    --protocol tcp \
    --description "Test" \
    --source-ips "127.0.0.1/32,127.0.0.2/32" \
    test
hcloud: source ips error on index 0: invalid CIDR address: 127.0.0.1/32,127.0.0.2/32
```

### Log output

```plain text

```

### Additional information

### Workaround

Until this is fixed, it can be worked around by specifying the flag once per value:

```shell
hcloud firewall add-rule --source-ips $IP1 --source-ips $IP2
```

### Issue

[HIDDEN]

### Additional contract requirements

- For firewall `add-rule` and `delete-rule`, `--source-ips` and `--destination-ips` must interpret comma-separated CIDR values as separate list entries.
