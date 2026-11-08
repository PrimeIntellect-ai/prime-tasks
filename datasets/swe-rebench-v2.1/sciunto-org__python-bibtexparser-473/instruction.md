Normalize field keys (to lowercase)
**Describe the bug**
I have several .bib files that contain (mixed) field keys that are either in lowercase or start with a capital letter, such as "Author" and "Title". No other tooling complains about this.

SeparateCoAuthors does not work and I cannot uniformy access the fields using e.g. `entry['title']`

A normalization to lowercase of the field keys was conducted in v1.

Maybe this can be fixed using a middleware? I would be really grateful!

**Reproducing**

Version: e3757c13abf2784bda612464843ab30256317e6c

Code:
```python

#!/usr/bin/python

import bibtexparser
import bibtexparser.middlewares as m

layers = [
	m.LatexDecodingMiddleware(),
	m.MonthIntMiddleware(True), # Months should be represented as int (0-12)
	m.SeparateCoAuthors(True), # Co-authors should be separated as list of strings
	m.SplitNameParts(True), # Individual Names should be split into first, von, last, jr parts
	m.MergeNameParts("last", True) # Individual Names should be merged oto Last, First...
]

bib_database = bibtexparser.parse_file('data/Survey.bib', append_middleware=layers)
for entry in bib_database.entries:
	print(entry['title']);
```

Bibtex:
```
@InCollection{Name2006,
  Title                    = {A Title},
  Author                   = {Name, First and Name, Second},
  Booktitle                = {ITS},
  Publisher                = {Some publisher},
  Year                     = {2006},
  Pages                    = {61--70}
}
```

**Remaining Questions (Optional)**
Please tick all that apply:

- [ ] I would be willing to contribute a PR to fix this issue.
- [ ] This issue is a blocker, I'd be grateful for an early fix.

### Additional contract requirements

- Add a public middleware class `NormalizeFieldKeys` in module `bibtexparser.middlewares.fieldkeys`.
- The constructor is `NormalizeFieldKeys(allow_inplace_modification: bool = True)`.
- `NormalizeFieldKeys.transform(library: Library) -> Library` returns a library in which every entry's field keys have been converted to lowercase.
- When two fields in the same entry normalize to the same lowercase key, the last field's value wins, and a warning is logged whose message begins with `NormalizeFieldKeys`.
