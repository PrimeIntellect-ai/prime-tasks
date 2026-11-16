regex in pattern filter only matches against start of string
### Expected Behavior
https://www.elastic.co/guide/en/elasticsearch/client/curator/current/filtertype_pattern.html#_regex suggests I can use a regex pattern to match anywhere in a string - for example use the pattern "y" to match an index name "xyz".

### Actual Behavior
regex only ever matches when the pattern starts at the beginning of the index name: for example index "xyz" matches "x" but not "y".

### Detailed Description
This happens because https://github.com/elastic/curator/blob/5.6/curator/indexlist.py#L451 (same in master at time of writing) [HIDDEN]

### Workarounds / Impact
It's confusing that this isn't clearly documented as a limitation.

You can work around this in some cases by inserting ".*" or equivalent at the beginning of the regex.  Unfortunately, I want to be able to pull the regex from an environment variable, but that doesn't support being combined with another string.  Overall, I want to be able to match indices with name "<constant text>.${environment variable}.*", which is currently impossible.  I think I'm going to have to add a startup wrapper to modify the environment variable and add .* to it.
