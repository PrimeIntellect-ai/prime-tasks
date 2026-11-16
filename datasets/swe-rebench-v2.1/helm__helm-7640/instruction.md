Support reading values from STDIN for `upgrade` command
#2709 introduced support for using STDIN with the "-" character for `install`. However, I don't think this works with the `upgrade` command.

My example usecase is decrypting a sops file and using the output in the `helm upgrade` command:


```sh
# I can do this and values in secrets.sops.yaml are available to the release:
sops -d secrets.sops.yaml | helm install -f - -f values.yaml my-release release/my-chart

# but this doesn't work:
sops -d secrets.sops.yaml | helm upgrade -f - -f values.yaml my-release release/my-chart
```
