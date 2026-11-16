Label with deeply nested input raises  form-control-has-label error
Hello,

I am implementing this package on one of my projects but I an running into an issue. I have a radio control component with the following structure:

```html
<label>
  <div>
    <input type="radio" />
  </div>
  <div>
      <slot />
  </div>
</label>
```

I am receiving an error related to the `form-control-has-label` rule, even if the input is correctly wrapped into a label tag.

I am not sure if it's related but in my ESLint config I've also added the following rule:

```
"vuejs-accessibility/label-has-for": [
      1,
      {
        "required": {
          "some": ["nesting", "id"]
        }
      }
    ]
```

Any hint on how to solve this problem?

Thank you in advance!
