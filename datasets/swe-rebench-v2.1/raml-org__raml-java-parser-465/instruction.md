date-only accepts values with more than 4 digits year
```
#%RAML 1.0
title: My Date API
types:
  birthday:
    type: date-only
    examples:
      good: 2015-05-23
      bad: 2016-13-33
      bad-2: 2016-12-33
      bad-3: 16-12-30
      bad-4: 20191-12-30
```

bad-3 and bad-4 should not be valid
