[css-grid] media rules are not inserted for grid-template[-areas] inside media queries
**Description**
[HIDDEN]
*NOTE:* This was working correctly in version 9.1.5.

**Expected Result**
For `grid-template-areas` declared within media queries, new media queries are inserted for each `grid-area` defined in the template.

**Proposed Solution**
I believe the bug was introduced in version 9.2:
https://github.com/postcss/autoprefixer/blob/2072e73d77fd1abc67e49f74950e3df2d6599026/lib/hacks/grid-utils.js#L606-L608
[HIDDEN]

**CSS Example to Reproduce**
Input:
```
.example {
  display: grid;
}

@media (max-width: 767.98px) {
  .example {
    grid-template-areas:
      'first first'
      'second third';
  }
}

.first {
  grid-area: first;
}

.second {
  grid-area: second;
}

.third {
  grid-area: third;
}
```

Current output:
```
.example {
  display: -ms-grid;
  display: grid;
}

@media (max-width: 767.98px) {
  .example {
        grid-template-areas:
      'first first'
      'second third';
  }
}

.first {
  grid-area: first;
}

.second {
  grid-area: second;
}

.third {
  grid-area: third;
}
```

Expected output:
```
.example[_ngcontent-c23] {
  display: -ms-grid;
  display: grid;
}

@media (max-width: 767.98px) {
  .example[_ngcontent-c23] {
        grid-template-areas: 'first first' 'second third';
  }
}

.first[_ngcontent-c23] {
  grid-area: first;
}

.second[_ngcontent-c23] {
  grid-area: second;
}

.third[_ngcontent-c23] {
  grid-area: third;
}

@media (max-width: 767.98px) {
  .first[_ngcontent-c23] {
    -ms-grid-row: 1;
    -ms-grid-column: 1;
    -ms-grid-column-span: 2;
  }
  .second[_ngcontent-c23] {
    -ms-grid-row: 2;
    -ms-grid-column: 1;
  }
  .third[_ngcontent-c23] {
    -ms-grid-row: 2;
    -ms-grid-column: 2;
  }
}
```


*NOTE:* While I was investigating this, I also noticed these lines:
https://github.com/postcss/autoprefixer/blob/2072e73d77fd1abc67e49f74950e3df2d6599026/lib/hacks/grid-utils.js#L534-L537
I have not run into any issues from this, but it looks like it was meant to be something like:
```
        if (rulesToInsert[lastArea].lastRule) {
          rulesToInsert[lastArea].lastRule.after(cloned)
        } else {
          rulesToInsert[lastArea].lastRule = cloned
        }
```

### Additional contract requirements

- When `grid-template-areas` is declared inside a media query, generate legacy grid-placement rules for every named `grid-area` under the corresponding media condition.
