progress bar and int id
If product id is an integer, it makes download progress bar crash:
```py
>>> from eodag import EODataAccessGateway
>>> dag = EODataAccessGateway()
>>> dag.set_preferred_provider("usgs")
>>> prods, _ = dag.search(productType="SENTINEL_2A")
>>> prods[0].properties["id"]
18933649
>>> prods[0].download()

Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
  File "/home/sylvain/workspace/eodag/eodag/api/product/_product.py", line 286, in download
    progress_callback.refresh()
  File "/home/sylvain/.virtualenvs/eodag-dev/lib/python3.8/site-packages/tqdm/std.py", line 1361, in refresh
    self.display()
  File "/home/sylvain/.virtualenvs/eodag-dev/lib/python3.8/site-packages/tqdm/std.py", line 1509, in display
    self.sp(self.__str__() if msg is None else msg)
  File "/home/sylvain/.virtualenvs/eodag-dev/lib/python3.8/site-packages/tqdm/std.py", line 1165, in __str__
    return self.format_meter(**self.format_dict)
  File "/home/sylvain/.virtualenvs/eodag-dev/lib/python3.8/site-packages/tqdm/std.py", line 475, in format_meter
    bool_prefix_colon_already = (prefix[-2:] == ": ")
TypeError: 'int' object is not subscriptable
```

[HIDDEN]

### Additional contract requirements

- Downloading a product with an integer ID must not crash because of the progress bar; the bar should display the ID as text.
