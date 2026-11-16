Support `tag:yaml.org,2002:merge` for parsing `!!merge <<: &foo`
**Is your feature request related to a problem? Please describe.**

In short, please add support for [`tag:yaml.org,2002:merge`](https://yaml.org/type/merge.html) for parsing `!!merge <<: &foo`.

Parsing the following yaml

```
const YAML = require('yaml')

YAML.parse(`
      foo: &foo
       a: 1
       b: 2
      bar:
       !!merge <<: *foo
`, {merge: true})
```

results in a warning

```
 (node:28408) [TAG_RESOLVE_FAILED] YAMLWarning: Unresolved tag: tag:yaml.org,2002:merge at line 6, column 8:

      bar:
       !!merge <<: *foo
       ^^^^^^^

```

While

```
YAML.parse(`
      foo: &foo
       a: 1
       b: 2
      bar:
       <<: *foo
`, {merge: true})
```

works fine.

**Describe the solution you'd like**

Parsing works without warning.

**Describe alternatives you've considered**

My workaround is currently adding the following custom tag:

```js
const YAML = require('yaml')

const mergeTag = {
  tag: 'tag:yaml.org,2002:merge',
  resolve(value) {
    return value;
  }
};

YAML.parse(`
      foo: &foo
       a: 1
       b: 2
      bar:
       !!merge <<: *foo
`, {merge: true, customTags: [mergeTag]})
```

which basically ignores the tag (if I am not mistaken).

**Additional context**

The problem came up, since `yq` is creating these tags automatically, when patching a yaml with a merge.
Here is an example

```sh
echo '
foo: &foo
  a: 1
  b: 2
bar:
   <<: *foo'  |
yq '.foo.a |= "b"'
```

which results in

```yaml
foo: &foo
  a: b
  b: 2
bar:
  !!merge <<: *foo
```

note the inserted `!!merge`.
