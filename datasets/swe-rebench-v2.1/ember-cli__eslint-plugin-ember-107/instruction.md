Nested Brace Expanded Properties
I get errors from `ember/use-brace-expansion` with something like this:

```javascript
  sampleProperty: computed(
    'foo.bar.{name,place}',
    'foo.baz.{thing,@each.stuff}',
    'foo.qux.[]',
    function() {
```

It doesn't pass until I nest them all like this:

```javascript
  sampleProperty: computed(
    'foo.{bar.{name,place},baz.{thing,@each.stuff},qux.[]}',
    function() {
```

This does not work. Ember does not support nested brace expansion, per [this comment/code](https://github.com/emberjs/ember.js/blob/master/packages/ember-metal/lib/expand_properties.js#L45).
