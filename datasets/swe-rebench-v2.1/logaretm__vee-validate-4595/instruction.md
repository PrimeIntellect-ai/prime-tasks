email validation rule regex is not correct
### What happened?

Regex used in email validation accepts invalid characters like # and $ and %

### Reproduction steps

1. Open sandbox
2. Type "email#%@test.com" (which obviously is a wrong email address) in input
3. No error will show

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

https://codesandbox.io/s/vee-validate-4-9-0-radio-group-forked-d6wgv8

### Code of Conduct

- [x] I agree to follow this project's [Code of Conduct](CONDUCT.md)

### Additional contract requirements

- The email validation rule must return `false` for `Pelé@example.com`.
