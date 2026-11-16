Installing stylelint-config-prettier may not be necessary?
I ran `ember-cli-update` to update a project that had `ember-source@v4.11.0` and `stylelint@v15.4.0` to version `4.12.0`. I noticed that the update added `stylelint-config-prettier` to `package.json`.

The [plugin's `README`](https://github.com/prettier/stylelint-config-prettier/blob/v9.0.5/readme.md) mentioned that it's not needed when `stylelint@v15` is installed:

> **Note**
> As of Stylelint v15 [all style-related rules have been deprecated](https://stylelint.io/migration-guide/to-15#deprecated-stylistic-rules). If you are using v15 or higher and are not making use of these deprecated rules, [this plugin is no longer necessary](https://stylelint.io/migration-guide/to-15#:~:text=Additionally%2C%20you%20may%20no%20longer%20need%20to%20extend%20Prettier%27s%20Stylelint%20config).

I wonder if we can remove `stylelint-config-prettier` from the blueprint since it adds `stylelint@v15`. There may be edge cases when an end-developer's project uses `stylelint` already; in such cases, the end-developer could always reject some of the changes made by `ember-cli-update`.

What are your thoughts?

---

A separate issue: [`stylelint-config-prettier` isn't listed in the `extends` key in `.stylelintrc.js`](https://github.com/ember-cli/ember-cli/blob/v4.12.0/blueprints/app/files/.stylelintrc.js).

https://github.com/prettier/stylelint-prettier/tree/v3.0.0#disabling-rules-that-may-conflict-with-prettier
