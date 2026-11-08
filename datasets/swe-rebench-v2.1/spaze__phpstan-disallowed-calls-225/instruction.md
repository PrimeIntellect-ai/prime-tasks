Supporting attributes restrictions on more targets, i.e. properties
Currently `disallowedAttributes` support only on attributes that target classes/interfaces/... or functions/methods (by [`AttributeUsages::processNode`](https://github.com/spaze/phpstan-disallowed-calls/blob/main/src/Usages/AttributeUsages.php#L68))

But attributes can have [other targets](https://www.php.net/manual/en/language.attributes.classes.php), I discovered this limitation while trying to restrict an attributes that is used on class properties.

I think it should be possible for `AttributeUsages` to support nodes for the other targets, but I'd like to know where @spaze stands on this:

1. lets add support for properties only, and see if someone else needs other targets in the future
2. lets support all possible attribute targets, by detecting the specific php parser nodes
3. lets support all possible attribute targets, by duck typing on attrGroups
4. not adding support for other attribute targets

I'd go for 2, let me know what you thing and if you'd welcome a PR (probably in a few weeks) or if you'd like to handle it directly
