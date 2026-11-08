categories with diacritics not handled well
Steps to reproduce:
1. Create a new task via interactive mode and set its category to `ý`.
2. Run `todo list -c ý`
3. The task is not listed.

I have tried setting `🤷` as a category as well to check whether it could be some more general encoding error, but this works.

I am using version 4.3.1 from the Void Linux repository.
