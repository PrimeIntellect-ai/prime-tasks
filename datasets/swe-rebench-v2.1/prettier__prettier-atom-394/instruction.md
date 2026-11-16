"Ignore Files in `.eslintignore`" does not work
<!--
Before you post an issue, please ensure that your issue is not with the
[prettier](https://github.com/prettier/prettier) or
[prettier-eslint](https://github.com/prettier/prettier-eslint) packages. This is just the
atom plugin that calls these packages under the hood.

Describe your issue here with as many details as possible
-->
By default this is enabled.
I added "test" in .eslintignore, so that linting ignores test files. Seems to work. Also disabled prettier formatting for my test files.
I disabled this feature in the prettier-atom config so I can prettify the test files.
I found that it did no prettifying on any of my test files on save.
I restarted atom and found the same.
Lastly, I removed "test" from .eslintignore and, on save of my test file, the prettifying started working again. So it definitely seems like this feature is having no effect.

I've done some research - I'm certain this is a feature specific to prettier-atom, not something in prettier or eslint themselves.

I'm afraid I can't figure out how to run Prettier: Debug (sorry!). But I can tell you I'm on 0.46.0 of the plugin.
<!--
Paste the output of the `Prettier: Debug` command below.
Protip: you can use a <details> tag to hide or show really large elements.

For example:
<details>
  A really long text
</details>
-->

### Additional contract requirements

- When the format-on-save option to respect `.eslintignore` is enabled, files matched by `.eslintignore` are not formatted on save.
- When that option is disabled, a file matched by `.eslintignore` remains eligible for format-on-save, subject to the other format-on-save conditions.
- A file not matched by `.eslintignore` remains eligible for format-on-save, subject to the other format-on-save conditions.
