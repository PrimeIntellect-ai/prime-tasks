Feature: Camelcase Javascript to JavaScript
### Type of feature

🍕 Feature

### Current behavior

This is not a priority but wanted to add this to the Papercut backlog.

Places we need this applied,
- Interests in profiles
- Interests in profile settings
- Insights explore dashboard

<img width="374" alt="Screen Shot 2023-01-31 at 3 09 42 PM" src="https://user-images.githubusercontent.com/5713670/215911414-9e508e9f-9c7f-4db3-bdcf-cc25c66c0ea4.png">
<img width="317" alt="Screen Shot 2023-01-31 at 3 11 47 PM" src="https://user-images.githubusercontent.com/5713670/215911490-3271e23d-f420-4b8a-8f61-e6dc18bd40a7.png">
<img width="671" alt="Screen Shot 2023-01-31 at 3 09 50 PM" src="https://user-images.githubusercontent.com/5713670/215911557-aeb45e2b-b069-4aed-b3b2-1cfb974718a0.png">


### Suggested solution

We have a solution in the hot repo for this, but we would need to sanitize content coming from the GitHub API. I believe everything is lowercase.

https://github.com/open-sauced/hot/blob/beta/src/lib/camelCaseToTitleCase.ts



### Additional context

_No response_

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Contributing Docs

- [ ] I agree to follow this project's Contribution Docs

### Additional contract requirements

- Add a public function `checkCamelCaseNaming(name: string): string` in `lib/utils/check-camelcase-naming.ts` (default export).
- When `name` equals `"javascript"` ignoring case, the function returns `"JavaScript"`.
- Otherwise the function returns the same string with its first character upper-cased.
- When `name` is falsy, the function returns an empty string.
