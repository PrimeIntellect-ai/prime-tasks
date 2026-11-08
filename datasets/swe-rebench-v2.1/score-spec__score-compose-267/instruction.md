resources list command reuse table library for UX standardization
In `provisioners list` command we introduced `github.com/olekukonko/tablewriter` to display the data,

To keep the same behavior across commands we can reuse it for `resources list` command

### Additional contract requirements

- With the default `resources list` output, render a table with `UID` and `Outputs` columns. List each resource's output names alphabetically, joined by `, `. For the resources in the existing example, the output must be:

```
+----------------------------+--------------+
|            UID             |   OUTPUTS    |
+----------------------------+--------------+
| dns.default#example.dns    | host         |
+----------------------------+--------------+
| volume.default#example.vol | source, type |
+----------------------------+--------------+
```
