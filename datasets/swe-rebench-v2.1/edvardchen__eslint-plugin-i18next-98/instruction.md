Whitespace around excluded words
I have indented jsx like this:
`return (`
`    <div className="alert alert-danger" role="alert">`
`        {t("No user details were found")}!`
`    </div>`
`)`

The plugin complains about the exclamation point. When I try to exclude it with "words": { exclude: ["!"] } the warning doesn't go away. If I remove the indentations in the jsx then the warning goes away. I had to add this to eslintrc: "words": { exclude: ["!\\s*"] } to ignore all whitespace after the exclamation point created by the indentation in order to get rid of the warning.

I think the plugin should ignore all whitespace at least created by indentation if not all whitespace.
