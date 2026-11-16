Incorrectly parses \\ in templates.
The template:

    {{FOO}} {{BAR}} {{FOO}}{{BAR}} {{FOO}}#{{BAR}} {{FOO}}//{{BAR}} {{FOO}}\\{{FOO}} {{FOO}}\\\\{{FOO}}\\\\{{FOO}}

Renders:

    foo bar foobar foo#bar foo//bar foo\\{{FOO}} foo{{FOO}}{{FOO}}

I have been looking through the handlebars spec regarding `\`, but I can't see anything specific about this in it; it seems like a bug.

Note that other various character variations, eg. "{{FOO}}xxxx{{BAR}}" are fine, it's just for `\`.

This tangibly manifests itself as a bug when rendering windows paths in templates, eg:

    {{BUILD_PATH}}\{{PROJECT_FOLDER_XXX}}
    Invalid template, ""while parsing a quoted scalar, found unknown escape character"

but:

    {{BUILD_PATH}}\\{{PROJECT_FOLDER_XXX}}
    renders: C:\projects\builds\source\artifacts\{{PROJECT_FOLDER_XXX}}

^ --- This is very surprising, and I'm pretty sure, not the correct behavior.

### Additional contract requirements

- In particular, with `FOO` set to `foo` and `BAR` set to `bar`, rendering the template `r"\\\\ {{FOO}} {{BAR}} {{FOO}}{{BAR}} {{FOO}}#{{BAR}} {{FOO}}//{{BAR}} {{FOO}}\\{{FOO}} {{FOO}}\\\\{{FOO}}\\\{{FOO}} \\\{{FOO}} \{{FOO}} \{{FOO}}"` must return `r"\\\\ foo bar foobar foo#bar foo//bar foo\foo foo\\\foo\\foo \\foo {{FOO}} {{FOO}}"`.
