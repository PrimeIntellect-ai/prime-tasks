Dirty check doesn't work when resetForm values contains optional field
### What happened?

Consider a use case where user types something in the form and then moves to some other page but forgets to save. In this case it would be nice to show a confirmation dialog to the user to verify if they want to leave the page without saving.

In order to do this, I'm using `meta` object `dirty` value to check if at least one field's value has been changed. When the user lands on the page then initial data is fetched from the backend server. I'm using `resetForm` to update the values and reset meta state just like it's described in here https://vee-validate.logaretm.com/v4/guide/composition-api/handling-forms/#setting-initial-values-asynchronously. This works for most fields but sometimes there's no "dirty check" for some other fields.

### Reproduction steps

Open stackblitz demo link

1. Type something in the 3rd field. - "Dirty check" works as expected.
2. Press `Reset` button. - This mimics API request, sets values and resets meta state.
3. Type something in the 3rd field. - "Dirty check" doesn't work at all.

I've observed that when `field1` is `undefined` then the last field's "dirty check" doesn't work. When `field1` is something else than `undefined` then "dirty check" works for all fields. I've also observed that when the order of `formSchema`'s `field2` and `field3` is changed, then `field2` dirty check doesn't work anymore but `field3` dirty check works.

### Version

Vue.js 3.x and vee-validate 4.x

### What browsers are you seeing the problem on?

- [X] Firefox
- [X] Chrome
- [ ] Safari
- [ ] Microsoft Edge

### Relevant log output

_No response_

### Demo link

https://stackblitz.com/edit/vitejs-vite-id7xmdvf?file=src%2FApp.vue

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](CONDUCT.md)

### Additional contract requirements

When `resetForm` installs asynchronously fetched values that include an optional property set to `undefined`, the form's dirty metadata is false immediately after the reset. Editing a field afterward makes the form's dirty metadata true.
