Certain footnote formatting makes letters disappear
### Version(s) affected

2.3.0

### Description

We have a lot of longer footnotes on the website and sometimes depending on the format it makes some letters disappear from the front of paragraphs.

```
My sentence[^1][^2][^3][^4]

---

[^1]: This footnote uses tabs to indent the following paragraphs, you will notice the first 3 letters are missing:

	Donec ac dolor blandit, laoreet est sed, ornare est. Nunc varius ligula sit amet leo varius tempus. Donec pharetra nisi at est pellentesque, non ultricies lorem fringilla.

	Donec ac dolor blandit, laoreet est sed, ornare est. Nunc varius ligula sit amet leo varius tempus. Donec pharetra nisi at est pellentesque, non ultricies lorem fringilla.

[^2]:
	This footnote uses tabs for all paragraphs.

	Donec ac dolor blandit, laoreet est sed, ornare est. Nunc varius ligula sit amet leo varius tempus. Donec pharetra nisi at est pellentesque, non ultricies lorem fringilla.

	Donec ac dolor blandit, laoreet est sed, ornare est. Nunc varius ligula sit amet leo varius tempus. Donec pharetra nisi at est pellentesque, non ultricies lorem fringilla.

[^3]: This footnote uses 4 spaces and it's working fine:

    Donec ac dolor blandit, laoreet est sed, ornare est. Nunc varius ligula sit amet leo varius tempus. Donec pharetra nisi at est pellentesque, non ultricies lorem fringilla.

    Donec ac dolor blandit, laoreet est sed, ornare est. Nunc varius ligula sit amet leo varius tempus. Donec pharetra nisi at est pellentesque, non ultricies lorem fringilla.


[^4]:
    This footnote uses four spaces for indenting all paragraphs and it's fine.

    Donec ac dolor blandit, laoreet est sed, ornare est. Nunc varius ligula sit amet leo varius tempus. Donec pharetra nisi at est pellentesque, non ultricies lorem fringilla.

    Donec ac dolor blandit, laoreet est sed, ornare est. Nunc varius ligula sit amet leo varius tempus. Donec pharetra nisi at est pellentesque, non ultricies lorem fringilla.
```

You can see a screenshot of how it renders, you can see the first two footnotes are missing 3 letters in some places.

![Screenshot 2022-06-02 at 14 22 47](https://user-images.githubusercontent.com/1446331/171628232-e4a0555f-4af5-42d0-8a59-3a82612b0386.png)




### How to reproduce

Here's a test file from my Laravel app:

```php
<?php

namespace Tests\Unit;

use League\CommonMark\Extension\Footnote\FootnoteExtension;
use Tests\TestCase;
use League\CommonMark\Environment\Environment;
use League\CommonMark\Extension\CommonMark\CommonMarkCoreExtension;
use League\CommonMark\MarkdownConverter;

class MarkdownFootnotesExtensionTest extends TestCase
{
    /** @test */
    public function multiline_footnotes_with_tabs_are_rendered()
    {
        // Configure the Environment with all the CommonMark parsers/renderers
        $environment = new Environment();
        $environment->addExtension(new CommonMarkCoreExtension());

        // Add this extension
        $environment->addExtension(new FootnoteExtension());

        // Instantiate the converter engine and start converting some Markdown!
        $converter = new MarkdownConverter($environment);
        $markdown = <<<MARKDOWN
Sentence[^1]

[^1]: This footnote uses tabs to indent the following paragraphs

	Donec ac dolor blandit, laoreet est sed, ornare est.

	Donec ac dolor blandit, laoreet est sed, ornare est.
MARKDOWN;

        $this->assertEquals(<<<HTML
<p>Sentence<sup id="fnref:1"><a class="footnote-ref" href="#fn:1" role="doc-noteref">1</a></sup></p>
<div class="footnotes" role="doc-endnotes"><hr /><ol><li class="footnote" id="fn:1" role="doc-endnote"><p>This footnote uses tabs to indent the following paragraphs</p>
<p>Donec ac dolor blandit, laoreet est sed, ornare est.</p>
<p>Donec ac dolor blandit, laoreet est sed, ornare est.&nbsp;<a class="footnote-backref" rev="footnote" href="#fnref:1" role="doc-backlink">↩</a></p></li></ol></div>

HTML, (string) $converter->convert($markdown));
    }
}
```

And the output that I receive:

```
  --- Expected
  +++ Actual

  -<p>Donec ac dolor blandit, laoreet est sed, ornare est.</p>\n
  -<p>Donec ac dolor blandit, laoreet est sed, ornare est.&nbsp;<a class="footnote-backref" rev="footnote" href="#fnref:1" role="doc-backlink">↩</a></p></li></ol></div>\n

  +<p>ec ac dolor blandit, laoreet est sed, ornare est.</p>\n
  +<p>ec ac dolor blandit, laoreet est sed, ornare est.&nbsp;<a class="footnote-backref" rev="footnote" href="#fnref:1" role="doc-backlink">↩</a></p></li></ol></div>\n
```

### Possible solution

[HIDDEN]

### Additional context

_No response_

### Did this project help you today? Did it make you happy in any way?

I love it but I wish there were more tutorials on how to make custom extensions! It looks super complicated... 🙈

### Additional contract requirements

- Tab-indented continuation paragraphs in footnotes must render with their leading text intact rather than dropping initial characters.
