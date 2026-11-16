Add database.info file
Once we have a database.sqlite file, we have no understanding of its contents. Investigating its contents requires
us to probe it via .sqlite.

A `database.sqlite` file should have an associated `database.info` file, which lists the contents of the
dataabse in an concise and informative way.

I would suggest a .csv with the following format:

```
entry number                         unique_id                           name                    unique_tag                     total_free_parameters                       finished
           0  a14161122b532586a68b69acdf10895c                 search_name[1]         dataset_tag_example_0                                         3                           True
           1  erfopiu7n9837nr9e9fnef0980e8fn0e                 search_name[1]         dataset_tag_example_1                                         3                           True
```

If we build a database from an output folder via `scrape` this info file should be created.

If the database is created via a session this info file should constantly be being updated.

### Additional contract requirements

- The summary should make each stored fit’s identifier, name, tag, total number of free parameters, and completion state understandable. The suggested table layout and column headings are examples, not requirements; in particular, no entry-number column or specific header names are required.
- Whenever changes to a session-backed database are committed, refresh the associated info file to reflect the persisted fits.
