Heading permalinks don't work if a document has the same title multiple times
<!-- Before submitting an issue, please use https://babelmark.github.io/ to compare how your Markdown input renders in other parsers. If all the CommonMark ones (including this one) show the same results then it's probably not a bug -->

**Version(s) affected**: 1.5.3

**Description**

When using the Heading permalinks, if a document has the same title multiple times, it creates the same link, which won't work

**How to reproduce**

```php
<?php

require "vendor/autoload.php";

use League\CommonMark\CommonMarkConverter;
use League\CommonMark\Environment;
use League\CommonMark\Extension\HeadingPermalink\HeadingPermalinkExtension;

// Obtain a pre-configured Environment with all the CommonMark parsers/renderers ready-to-go
$environment = Environment::createCommonMarkEnvironment();

// Add this extension
$environment->addExtension(new HeadingPermalinkExtension());

// Instantiate the converter engine and start converting some Markdown!
$converter = new CommonMarkConverter([], $environment);
echo $converter->convertToHtml("# Hello World!\n## Title\n## Title");
```

Outputs
```
<h1><a id="user-content-hello-world" href="#hello-world" name="hello-world" class="heading-permalink" aria-hidden="true" title="Permalink">¶</a>Hello World!</h1>
<h2><a id="user-content-title" href="#title" name="title" class="heading-permalink" aria-hidden="true" title="Permalink">¶</a>Title</h2>
<h2><a id="user-content-title" href="#title" name="title" class="heading-permalink" aria-hidden="true" title="Permalink">¶</a>Title</h2>
```

The second `#title` should be `#title-1` or `#title-2`

I checked on babelmark; https://babelmark.github.io/?text=%23+title%0A%23%23+title and it's not clear what the take is on this.

I would love to use your implementation and throw away the ... thing ... I made for Daux : https://github.com/dauxio/daux.io/blob/master/libs/Format/HTML/ContentTypes/Markdown/TOC/Processor.php#L71

It's an all-in-one solution to add IDs to headers and create a Table of Contents.
The separation you made between headings and TOC seems way cleaner and I'll adopt it once it can do multiple titles as well.

P.S. Thanks for maintaining this parser, it's a really neat implementation and easy to use :)
