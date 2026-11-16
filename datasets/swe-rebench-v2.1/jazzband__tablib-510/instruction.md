"Invalid character / found in sheet title" during export to XLSX
Hi there,

it looks like tablib could automatically replace some characters when exporting to XLS, what do you think? The problem occurs when I export a sheet with a slash inside its title:

```
  File "/Users/mpasternak/.virtualenvs/bpp/lib/python3.8/site-packages/tablib/formats/_xlsx.py", line 53, in export_book
    ws.title = dset.title if dset.title else 'Sheet%s' % (i)
  File "/Users/mpasternak/.virtualenvs/bpp/lib/python3.8/site-packages/openpyxl/workbook/child.py", line 93, in title
    raise ValueError(msg)
ValueError: Invalid character / found in sheet title
```

Devs, please let me know if this is desired and I'll think about a patch.

### Additional contract requirements

- For XLSX exports, replace each `\`, `/`, `*`, `?`, `:`, `[` and `]` in sheet titles with `-`, and truncate the resulting title to 31 characters. Exporting a Dataset or Databook with the title `bad name \/*?:[]qwertyuiopasdfghjklzxcvbnm` must produce the round-tripped title `bad name -------qwertyuiopasdfg`.
