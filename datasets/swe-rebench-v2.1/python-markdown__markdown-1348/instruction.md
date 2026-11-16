SmartyPants: Apostrophes at the start of leading contractions
As mentioned in the original project [here](https://daringfireball.net/projects/smartypants/#:~:text=or%20email%20client.-,ALGORITHMIC%20SHORTCOMINGS), "SmartyPants will turn the apostrophe into an opening single-quote, when in fact it should be a closing one."

This is specifically presenting an issue for me when `smarty` collides with `abbr`. For instance, this code:

```
Each section of the editor controls an access group's ability to view, and actions within, the listed pages.
Select the checkboxes to allow the appropriate actions.

*[access group]: Access groups allow admin users to<br>assign custom permissions to all<br>users assigned to that group.
```

is rendering like this:

![image](https://user-images.githubusercontent.com/97999520/202307054-76b288f7-ed2e-4712-8f58-4d0d0b03b9d4.png)

because when `access group` gets rendered by `abbr`, the `'` is no longer recognized as being mid-word and instead renders as a leading single quote for the possessive `s`.

I've implemented a stopgap via javascript, but there are a lot of different contraction situations and it would be great to have a real fix.

### Additional contract requirements

- When a possessive apostrophe follows emphasized or abbreviated text, SmartyPants must render it as `&rsquo;`.
