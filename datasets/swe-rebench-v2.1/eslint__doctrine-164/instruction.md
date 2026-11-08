Support case insensitive tags
**What version are you using?**
master

**What JSDoc comment were you trying to parse?**
/** @Const {String} constname */

**What Doctrine options were you using (sloppy, unwrap, etc.)?**
{ unwrap: true }

**What happened? Include output if possible.**
Tag gets parsed as
```
{ description: '{String} constname', title: 'Const' }
```

**What did you expect to happen?**
Tag gets parsed as
```
{
  description: null,
  name: 'constname',
  title: 'Const',
  type: { name: 'String', type: 'NameExpression' }
}
```

See eslint related issues: https://github.com/eslint/eslint/issues/6121 https://github.com/eslint/eslint/issues/6145
