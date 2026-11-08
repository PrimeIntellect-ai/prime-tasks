Plural component requires extract string on each update
**Describe the bug**
In development, when I update strings inside a `<Plural>` I have to run extract-strings to render those updated strings properly. I do not have to do that for strings marked for translation inside `i18n.()`.  Is this expected.

**To Reproduce**
Create <Plural count={jobs} one= "job" other="jobs"/>

replacing the Plural component with the raw I18n function also does not render the proper string until I extract the the strings.
`i18n._(
                    '{numItemsToDelete, plural, one {The inventory will be in a pending status until the final delete is processed.} other {The inventories will be in a pending status until the final delete is processed.}}',
                    { numItemsToDelete: selected.length }
                  )`


refresh the screen.
**Expected behavior**
Expect that when count is 1 string = job and when count is >1 string  = jobs
**Additional context**
Something like "{0, plural, one {You do not have permission to cancel the following job:} other {You do not have permission to cancel the following jobs:}}" is rendered.  Notice both strings are rendered inside of the {}

My concern here is that if I extract the strings each time they change in order to get them to render properly while in dev. mode I will have a lot of noise in my PRs with these changes, and also that when I ship the compiled strings out to the translation contractors, that actually do the translations, there will be all sorts of merge conflicts when they come back.

- jsLingui version ``3.7.1``
- Babel version ``7.0.0``
- Create React App
