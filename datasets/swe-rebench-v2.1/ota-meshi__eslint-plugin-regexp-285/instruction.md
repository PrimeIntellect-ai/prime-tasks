`no-useless-flag` needs better error messages
![image](https://user-images.githubusercontent.com/20878432/122079371-a1ce3d80-cdfd-11eb-8f84-3e3170220509.png)

> The 'g' flag is unnecessary because not using global testing.

The current error message doesn't really say anything. A better error message would be: "The 'g' flag is unnecessary because `String.prototype.split` ignores the 'g' flag." or something like that.

Same problem for other string methods and flags.

Also, now that I got the error message: What's "global testing" @ota-meshi?

---

I wound how we could fix this.

The current implementation seems to mark flags as used. [HIDDEN] Would that work?

### Additional contract requirements

- Report each unnecessary-flag diagnostic at the location of the unnecessary flag.
- Use the following exact wording for improved report messages:
  - A `g`-flag regex used only once in `RegExp.prototype.test`: `The 'g' flag is unnecessary because the regex is used only once in 'RegExp.prototype.test'.`
  - A `g`-flag regex used only once in `RegExp.prototype.exec`: `The 'g' flag is unnecessary because the regex is used only once in 'RegExp.prototype.exec'.`
  - A `g`-flag regex used in `String.prototype.search`: `The 'g' flag is unnecessary because 'String.prototype.search' ignores the 'g' flag.`
  - A `g`-flag regex used in `String.prototype.split`: `The 'g' flag is unnecessary because 'String.prototype.split' ignores the 'g' flag.`
  - A `g`-flag regex whose unnecessary use is not explained by a single method (for example, it is used in more than one way): `The 'g' flag is unnecessary because the regex does not use global search.`
  - A `y`-flag regex used in `String.prototype.split`: `The 'y' flag is unnecessary because 'String.prototype.split' ignores the 'y' flag.`
- Autofix by removing the unnecessary flag when the regex is used directly (the regex literal or `new RegExp(...)` expression is passed directly to the method) and only once. When the regex is referenced through a variable, do not provide an autofix.
