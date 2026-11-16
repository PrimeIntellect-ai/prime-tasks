label-has-for doesn't report errors if there is no control wrapped inside
I'm using the accessibility plugin, especially the rule `label-has-for`. My configuration looks like the following:

```js
    'vuejs-accessibility/label-has-for': [
      'error',
      { required: { some: ['nesting', 'id'] } },
    ],
```

The problem is that the rule doesn't fire when I use it like that:

```html
<label>
  <div></div>
</label>
```

It only fires when there is no elements in it:

```html
<label></label>
```

II think the `nesting` validation rule is broken. I took a look at the implementation and I think [this line](https://github.com/vue-a11y/eslint-plugin-vuejs-accessibility/blob/3715f6dbf3eecbd47ccf4530577d7e7a34813166/src/rules/label-has-for.js#L15) is incomplete. It should check if there is a form control inside the children 🙂
