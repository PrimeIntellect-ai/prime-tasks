Add enableReinitialize option and set it to false by default
Currently, if you pass `initialValues`, you can overwrite them by passing another value - the form will update its values.

This brings a problem when your data is stored for example in redux or in another component. You get this data and pass into form. Once this values are changed (in redux / another component) - your form *magically* updates and removes all data you've changed.

In redux-form there is a nice [enableReinitialize](https://redux-form.com/7.0.4/docs/api/reduxform.md/#-code-enablereinitialize-boolean-code-optional-) option which is `false` by default. You can set it to `true` and your form will update itself.

I think, the same behavior and option should be added to formik so your data won't suddenly disappear.

---

Related issues - https://github.com/jaredpalmer/formik/issues/163, https://github.com/jaredpalmer/formik/issues/164

For the first related issue, there is [keepDirtyOnReinitialize](https://redux-form.com/7.0.4/docs/api/reduxform.md/#-code-keepdirtyonreinitialize-boolean-code-optional-) option which prevents form from refreshing dirty values on `initialValues` change.

### Additional contract requirements

- Add an `enableReinitialize?: boolean` option to the Formik configuration. It defaults to `false`. When it is `true`, Formik resets the form whenever `initialValues` change (compared using deep equality); when it is `false` or omitted, changing `initialValues` does not reset the form.
- Expose `initialValues` as a read-only computed prop to consumers and through context. It is the current `initialValues` passed to Formik, or an empty object when none is provided.
