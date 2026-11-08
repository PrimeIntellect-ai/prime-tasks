Annif does not adhere umask setting for data files
Annif uses `tempfile.mkstemp()` for saving some vocabulary and project data files in the [`atomic_save()` method](https://github.com/NatLibFi/Annif/blob/736353f3b57f8647a8fa127c7a3b0cbba5ef0b31/annif/util.py#L40). The file permissions of the files created are always only read and write for the owner; the permissions cannot be set by umask ([Python docs](https://docs.python.org/3/library/tempfile.html#tempfile.mkstempare)).

For example:
```
umask 0007  # normally results to permission -rw-rw----

annif load-vocab arch tests/corpora/archaeology/yso-archaeology.ttl
ls -l data/vocabs/arch/
total 76
-rw------- 1 <myuser> <mygroup> 10597 Jan 27 13:10 subjects.csv
-rw------- 1 <myuser> <mygroup> 29177 Jan 27 13:10 subjects.dump.gz
-rw-rw---- 1 <myuser> <mygroup> 32252 Jan 27 13:10 subjects.ttl
```
As seen above, only `subjects.ttl` gets the desired permissions (because that file is [just copied](https://github.com/NatLibFi/Annif/blob/736353f3b57f8647a8fa127c7a3b0cbba5ef0b31/annif/corpus/skos.py#L148) to the vocabulary directory).

This is a problem for multiuser environments. The same problem might exist also in some of the libraries Annif uses and which save data files, but not in Omikuji. The backends use that create the `vectorizer` file are affected via Annif's `atomic_save()`.

[HIDDEN]

### Additional contract requirements

- Files written by `atomic_save()` must have permission bits corresponding to `0o666 & ~umask`; for example, a umask of `0007` yields mode `0660` (`rw-rw----`).
