Possibility to remove line-numbers from extraction metadata
Would it be reasonable to add an option to exclude line numbers from the file references?

I totally love the references and their ability to communicate in which file a certain translation is used
but in most cases the file number isn't super relevant and is creating the need to re-extract the translations
even if I'm just making a newline in one of my files. It would also prevent small commits from creating a lot of changes.

I'd gladly help out by sending a PR but wanted to check in to see if it's something that would be valuable before committing my time? :)

### Additional contract requirements

The public `:write_reference_line_numbers` configuration key controls whether extracted file references include line numbers. Setting it to `false` omits line numbers while retaining the referenced file names; when the option is not set, references continue to include line numbers. This option does not override `:write_reference_comments: false`, which omits references entirely.
