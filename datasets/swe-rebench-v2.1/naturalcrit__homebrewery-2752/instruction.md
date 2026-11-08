Brew crashes due to multiple text formatting tags
### Renderer

v3

### Browser

Chrome

### Operating System

Windows

### What happened?

I was fixing my table of contents for my brew (which is still bricked), and suddenly the entire browser went into a full white screen aside from the address bar at the top. After some digging, I was able to determine that this is the result of putting two {} text formatting brackets below one another (presumably the second one attempts to format the first one, which leads to undesired behaviour). The code provided is an example of what I had.

While I was able to save and create another brew using the source code from this one, I would prefer to still keep the previous one to use the same link, as well as partially to keep it as one of my top viewed brews to ease finding it in my pile of brews on my profile.

If you are able to manually change the contents of a brew, please remove the provided bit from page 2 of brew:
https://homebrewery.naturalcrit.com/edit/PRK9DJ9Cm

### Code

```gfm
##### [Grievous Wounds](#p27)
{color:#73310e,font-size:125%}
{text-align:center}
```

### Additional contract requirements

- For these consecutive injection cases, Markdown rendering must produce exactly the shown HTML:

- `{{dog Sample Text}}{cat}{toad}`: `<p><span class=" cat"   class="inline-block cat"  >Sample Text</span></p>\n`
- `{{dog\nSample Text\n}}\n{cat}\n{toad}`: `<div class=" cat"   class="block cat"  ><p>Sample Text</p>\n</div><p>{toad}</p>\n`
