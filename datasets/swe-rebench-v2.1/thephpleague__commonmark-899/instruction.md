Incorrect rendering of Embed after a list block
### Version(s) affected

2.3.3

### Description

An embeddable link used after a list gets rendered as a paragraph rather than getting embedded. In the code below, the first embed is rendered as a paragraph, the second one is rendered correctly as an iframe.

### How to reproduce

``` php
use League\CommonMark\Environment\Environment;
use League\CommonMark\Extension\CommonMark\CommonMarkCoreExtension;
use League\CommonMark\Extension\Embed\Bridge\OscaroteroEmbedAdapter;
use League\CommonMark\Extension\Embed\EmbedExtension;
use League\CommonMark\MarkdownConverter;

require 'vendor/autoload.php';

$config = [
    'embed' => [
        'adapter' => new OscaroteroEmbedAdapter(),
        'allowed_domains' => ['youtube.com'],
        'fallback' => 'link',
    ],
];

$environment = new Environment($config);
$environment->addExtension(new CommonMarkCoreExtension());
$environment->addExtension(new EmbedExtension());
$converter = new MarkdownConverter($environment);

$markdown = <<<MARKDOWN
# Embed Bug

- Hello
- World

https://www.youtube.com/watch?v=dQw4w9WgXcQ

https://www.youtube.com/watch?v=dQw4w9WgXcQ
MARKDOWN;

echo $converter->convert($markdown);
```

### Additional contract requirements

- When the Autolink extension is enabled, a standalone embeddable URL indented by three spaces, such as `https://www.youtube.com/watch?v=dQw4w9WgXcQ`, must render as `<iframe class="embed" src="https://www.youtube.com/watch?v=dQw4w9WgXcQ"></iframe>`.
- With Autolink enabled, an embeddable URL inside a list item must not render as an iframe; it remains text in the list item, such as `<li>https://www.youtube.com/watch?v=dQw4w9WgXcQ`.
