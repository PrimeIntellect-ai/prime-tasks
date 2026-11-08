Switching between fields with same name causes validation field value to be empty
### What happened?

Basically there is a case where switching between two components which use `useField` with same `name` will cause the latter's `field.value` to become undefined. It breaks certain cases like for example
```
<template v-if="value === 1">
    <MyInput name="test" />
</template>
<template v-if="value === 2">
    <MyInput name="test">
</template>
```
and also hot reloading seem to be affected by this to some degree.
From what I've checked it seems that the culprit may be the fact that fields are "unregistered" asynchronously in `nextTick` which causes flow like this:
1. first component gets rendered and it's form value is set
2. first component gets unmounted and "destroy" of field in form is scheduled to next tick
3. second component gets rendered and it's set properly
4. after a brief moment (next tick) the "destroy" runs making `field.value` in second component equal to `undefined`

I believe the solution could be to [HIDDEN], so scheduled "destroy" would not happen on this field.

Given two examples:
https://stackblitz.com/edit/vue-3-veevalidate-form-validation-example-sahnmn?file=src%2Fvee-validate.esm.js,package.json,src%2FField.vue,src%2FApp.vue
This one seems to work properly (4.5.1) and field value stays as "test".

Here:
https://stackblitz.com/edit/vue-3-veevalidate-form-validation-example-1dlyi1?file=src%2Fvee-validate.esm.js,package.json,src%2FField.vue,src%2FApp.vue
Field value will become undefined.

The only workaround (which seem to not be ideal) is something I created in second example:
![image](https://github.com/logaretm/vee-validate/assets/3301242/0bc4fb5f-7782-41e0-b003-0603bd2f0311)
If return is commented/removed then it will evaluate AFTER the scheduled removal and "overwrite" the undefined value.
### Reproduction steps

Check both examples and look for "Field value"

### Version

Vue.js 3.x and vee-validate 4.x

### What browsers are you seeing the problem on?

- [ ] Firefox
- [X] Chrome
- [ ] Safari
- [ ] Microsoft Edge

### Relevant log output

_No response_

### Demo link

provided in description

### Code of Conduct

- [X] I agree to follow this project's [Code of Conduct](CONDUCT.md)

### Additional contract requirements

- If a field is replaced by another `useField` field with the same name before the first field’s deferred cleanup runs, that cleanup must not make the replacement field’s value `undefined`.
