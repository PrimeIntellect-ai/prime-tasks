The `enforce-repeated-arg-type-style` rule finds some false positives.
**Describe the bug**
The `enforce-repeated-arg-type-style` rule finds some false positives. I will demonstrate this using the repository https://github.com/influxdata/telegraf (over 650k lines) as an example.

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I cloned repo and switched to particular branch
```
git clone https://github.com/influxdata/telegraf.git
cd telegraf
git checkout v1.31.3
```
3. I run it with the following flags & configuration file:
```shell
# flags
revive -config revive.toml ./... | sort
```
```toml
#revive.toml
[rule.enforce-repeated-arg-type-style]
  arguments = ["short"]
```
4. Some of the findings are false positives.

**Expected behavior**
I would like only the findings that are not false positives to be shown.

**Logs**
Some examples:

`plugins/inputs/webhooks/artifactory/artifactory_webhook.go:23:87: repeated argument type can be omitted`:
![image](https://github.com/user-attachments/assets/43d3fd8c-c391-4fb3-ae89-8567ccac2543)

`plugins/outputs/bigquery/bigquery.go:244:45: repeated argument type can be omitted`:
![image](https://github.com/user-attachments/assets/b4d35730-50dc-48ce-9a1e-5dcb565a3ec2)

`plugins/outputs/mqtt/mqtt_test.go:803:59: repeated argument type can be omitted`:
![image](https://github.com/user-attachments/assets/b1bfd5ff-ef49-4aea-9fe4-45307a044e7e)


**Desktop (please complete the following information):**
 - OS: Ubuntu 23:10
 - Version of Go:
```shell
$ go version
go version go1.23.0 linux/amd64
```

### Additional contract requirements

For the short argument style, report genuinely repeated argument types, but do not report distinct unresolved imported type expressions as repeated merely because type resolution represents both as invalid.
