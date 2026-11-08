Allow realpath on each filenames for `checkstyle` and `junit` reports

Hello,

IMO, it's always difficult to re-use reports generated (whatever format) with relative filenames, on third-party tool.

As author of package https://github.com/llaville/sarif-php-converters (still under development),
I've a `Console Tool` that is able to convert a report from `checkstyle` format to `sarif`.
But it's almost impossible if source provider did not send the absolute path on each files.


When we lint a source (e.g: Twig-CS-Fixer repo itself)

```shell
devilbox@php-8.2.20 in /shared/backups/forks/Twig-CS-Fixer $ bin/twig-cs-fixer lint --report checkstyle
```

We got such kind of report

```xml
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="./tests/Runner/Fixtures/Linter/node_visitor.twig">
    <error line="5" column="16" severity="error" message="Expecting 0 whitespace after &quot;|&quot;; found 1." source="TwigCsFixer\Rules\Punctuation\PunctuationSpacingRule"/>
    <error line="5" column="16" severity="error" message="Expecting 0 whitespace before &quot;|&quot;; found 1." source="TwigCsFixer\Rules\Punctuation\PunctuationSpacingRule"/>
    <error line="13" column="20" severity="error" message="Expecting 0 whitespace after &quot;|&quot;; found 1." source="TwigCsFixer\Rules\Punctuation\PunctuationSpacingRule"/>
    <error line="13" column="20" severity="error" message="Expecting 0 whitespace before &quot;|&quot;; found 1." source="TwigCsFixer\Rules\Punctuation\PunctuationSpacingRule"/>
    <error line="4" column="1" severity="error" message="More than 1 empty line is not allowed, found 3" source="TwigCsFixer\Rules\Whitespace\EmptyLinesRule"/>
    <error line="8" column="1" severity="error" message="More than 1 empty line is not allowed, found 3" source="TwigCsFixer\Rules\Whitespace\EmptyLinesRule"/>
    <error line="12" column="1" severity="error" message="More than 1 empty line is not allowed, found 3" source="TwigCsFixer\Rules\Whitespace\EmptyLinesRule"/>
    <error line="16" column="1" severity="error" message="More than 1 empty line is not allowed, found 3" source="TwigCsFixer\Rules\Whitespace\EmptyLinesRule"/>
    <error line="20" column="1" severity="error" message="More than 1 empty line is not allowed, found 3" source="TwigCsFixer\Rules\Whitespace\EmptyLinesRule"/>
    <error line="24" column="1" severity="error" message="More than 1 empty line is not allowed, found 3" source="TwigCsFixer\Rules\Whitespace\EmptyLinesRule"/>
    <error line="28" column="1" severity="error" message="More than 1 empty line is not allowed, found 3" source="TwigCsFixer\Rules\Whitespace\EmptyLinesRule"/>
  </file>

  <...MORE...>

</checkstyle>
```

> [!WARNING]
>
> Look deep on file names (relative paths)

It may be solved quickly, if we specify the absolute path to source to analyse

```shell
devilbox@php-8.2.20 in /shared/backups/forks/Twig-CS-Fixer $ bin/twig-cs-fixer lint --report checkstyle /shared/backups/forks/Twig-CS-Fixer
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle>
  <file name="/shared/backups/forks/Twig-CS-Fixer/tests/Runner/Fixtures/Linter/node_visitor.twig">

```

But there is also an alternative to fix it by PR.

Are you agree with such request ?
