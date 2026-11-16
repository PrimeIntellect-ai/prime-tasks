Allow named exports to have underscores in names
<!--
  Issues are so 🔥

  If you remove or skip this template, you'll make the 🐼 sad and the mighty god
  of Github will appear and pile-drive the close button from a great height
  while making animal noises.

  👉🏽 Need support, advice, or help? Don't open an issue!
  Head to StackOverflow or https://gitter.im/webpack/webpack.
-->

- Operating System: macOS 10.15.6
- Node Version: 12.18.4
- NPM Version: 6.14.6
- webpack Version: 4.44.2
- css-loader Version: 4.3.0

### Feature Proposal

When I set css-loader options like this:

```js
{
    loader: 'css-loader',
    options: {
        modules: {
            namedExport: true,
            exportLocalsConvention: 'dashesOnly',
        },
    }
},
```

The loader emits an error for each CSS file: `The "modules.namedExport" option requires the "modules.exportLocalsConvention" option to be "camelCaseOnly"`.

I understand that class names mustn't contain dashes and many other characters to be able to be constant names, but underscore (`_`) is allowed and I want to use it in constant names.

In order to achieve this, there can be a value like `leaveUnderscore` for the `exportLocalsConvention` option that shall camelize everything except underscores and be accepted when `namedExports` is `true`.

### Feature Use Case

BEM. Even though CSS modules make BEM be completely meaningless, underscore can be used to split logical parts in CSS class names, especially when CSS is produced by a preprocessor. For example, here is my SCSS:

```sass
.button {
    &_label {
    }
}
.label {
    &_icon {
    }
}
```

I want to use the class names as is:

```
import {button, button_label, label, label_icon} from './style.scss?module';
```

### Additional contract requirements

- When `modules.namedExport` is `true` and `modules.exportLocalsConvention` is set to any value other than `"camelCaseOnly"` or `"dashesOnly"`, the loader must fail with the error message: `The "modules.namedExport" option requires the "modules.exportLocalsConvention" option to be "camelCaseOnly" or "dashesOnly"`.
