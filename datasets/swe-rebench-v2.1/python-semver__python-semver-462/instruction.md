semver.bump_prerelease on *-rc9 results in lower version
### Which version of Python is the problem with?

3.8

### What semver version are you using?

_No response_

### What OS are you using? (Add more in the Environment section)

macOS

### Situation

When calling semver.bump_prerelease on a version with a prerelease of `-rc9`, it gets bumped to `-rc10`. However. according to the semver spec (https://semver.org/#spec-item-11 section 11.4 items 1+2), 'rc9' is considered a string and will be compared to 'rc10' using ASCII sort order, which considers 'rc10' to be lower than 'rc9'.

### How to reproduce

```
>>> import semver
>>> version1 = '1.0.0-rc9'
>>> version2 = semver.bump_prerelease(version1)
>>> version2
'1.0.0-rc10'
>>> semver.compare(version1, version2)
1
```



### Expected behavior

Not entirely sure how the bump_prerelease version should behalve when it gets `rc9`. ASCII-wise, after `9` you could consider `a`, but you get `rca`, `rcb` which feels a bit odd. Another option could be that the function just returns some kind of error, indicating it cannot determine how to increase `rc9` to a higher value.

### Environment

_No response_
