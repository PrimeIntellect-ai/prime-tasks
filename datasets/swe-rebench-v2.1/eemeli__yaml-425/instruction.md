Custom tags are printed on newline instead of after the key
**Describe the bug**
I am creating custom tags that handles non scalar values. The way the yaml is formatted though is unexpected. See below:

Expected:
```
foo:
  bar: !append
    - hello
    - world
```

Actual
```
foo:
  bar:
    !append
    - hello
    - world
```

**To Reproduce**
Here is my code:

```
const APPEND_PATCH = {
  tag: '!append',
  identify: value => value.tag === '!append',
  createNode: (_, item) => {
    const x = new yaml.YAMLSeq();
    x.tag = '!append';
    item.value.forEach(v => x.add(v));
    return x;
  },
}

class AppendPatch {
  tag = '!append';
  value;

  constructor(val) {
    this.value = val;
  }
}

const TEST = {
  foo: {
    bar: new AppendPatch(['hello', 'world'])
  }
}

const result = yaml.stringify(struct, {
    nullStr: '~',
    customTags: [APPEND_PATCH],
  });

console.log(result);
```
