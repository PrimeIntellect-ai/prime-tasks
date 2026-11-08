`isValid` is true even when there are invalid fields
#97 introduces `isInitialValid` which marks the form invalid when it's initialized. This gives a confusing result as soon as the form is dirty.

[HIDDEN] In our project we observed this as a submit button going from disabled to enabled after entering a valid value into an input, even though the other fields weren't valid. This feels like an unexpected behaviour.

Do you have a pattern to deal with this? I understand that you don't want fields to show errors until they're been blurred, but for this case I'd expect formik to keep track of invalid fields even if they haven't been touched

Thanks
Adam

### Additional contract requirements

- Once a form is dirty, `isValid` depends only on the form's validation errors: it is `false` when any validation error exists (including errors on fields that have not been touched) and `true` when there are no validation errors.
