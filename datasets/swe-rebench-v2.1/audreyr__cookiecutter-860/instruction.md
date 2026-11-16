pre_gen hook doesn't appear to be loading custom extensions
Latest version of cookiecutter from master. Last commit [ceafa1dc1b5eb70835ffba5dc7457df269d77ba8](https://github.com/audreyr/cookiecutter/commit/ceafa1dc1b5eb70835ffba5dc7457df269d77ba8)

In my pre_gen_project hook, I have this code: `{{cookiecutter.should_be_list | to_sequence}}` which turns a string into a list but cookiecutter raises a TemplateAssertionError `jinja2.exceptions.TemplateAssertionError: no filter named 'to_sequence'`. I know that my to_sequence filter isn't the issue because when I use it in other parts of my template and remove it from the pre_gen hook, everything executes successfully.

Are the custom extensions intended to only be loaded after the pre_gen hook is finished executing?
