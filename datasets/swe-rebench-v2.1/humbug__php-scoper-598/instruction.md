Restrict possible delimiters for regexes
In PHP in practice any character can be used for regexes. In the context of PHP-Scoper, i.e. matching symbols fully qualified names against regexes, various delimiters are causing issues. For example `\` which makes `\Foo\A` a perfectly valid case or `Bar\BW` for which `B` works out.

For this reason I think it's simpler to restrict regexes to special characters (i.e. non unicode letters) and exclude `\` as well.
