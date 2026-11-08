Cannot get Canonical for Instances when url is assigned via a RuleSet
Reported by Brian Kaney on Zulip: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Canonical.20with.20rule-set

Suppose a rule-set that sets the URL and version
```
RuleSet: LibraryMetadata(id)
* url = "http://fhir/ig/Library/{id}"
* version = "0.1.0"
```

When I insert it in a resource, called MyLibrary and try to make a canonical reference, it fails:
```
* library = Canonical(MyLibrary)
```

with:
> error Cannot use canonical URL of MyLibrary because it does not exist. Be sure that MyLibrary exists and it has a URL.

It seems that unless url is explicitly set (e.g. not via a rule-set), the canonical doesn't work...
