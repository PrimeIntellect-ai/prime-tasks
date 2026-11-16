Bug: Add space need to ignore filenames
Turn on the option "Space between Chinese Japanese or Korean and English or numbers"

```html
before
<img src="中文small.png" />

after
<img src="中文 small.png" />
```
Then the image file won't be found.
