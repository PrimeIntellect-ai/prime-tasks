Guides - components.md - vague conclusion concerning the different roles function components play
### Environment

* Phoenix version (mix deps): 1.7.1

### Expected behavior

* the guide should mention the attribute syntax example `messenger={@messenger}` **before** using this snipped in its conclusion concerning "the different roles function components play"

### Actual behavior
* in line 73 in components.md, it is said:
"[...], as we called `<.greet messenger={@messenger} />` from `show.html.heex`"
* but `messenger={@messenger}` is not mentioned before (so newcomers working with the guide have not called it yet)
* in line line 55, the guide gives only general information by mentioning `<.greet messenger="..." />`and `<HelloWeb.HelloHTML.greet messenger="..." />`
