Ability to instantiate a new instance of the Color class with a HEX color as well as RGB.
**Is your feature request related to a problem? Please describe.**
It's not a big problem, but as a web developer and designer, I work with hex color values much more often than RGB values.

**Describe the solution you'd like**
I really like that you can use hex in _markup_ - but you can't actually create an instance of the `Color` class with a hex value. I have a helper function that automatically converts hex to RGB to fill this void, but it would be great to avoid that step entirely.

**Describe alternatives you've considered**
Just using a helper function to convert to HEX on the fly.

**Additional context**
Example (Note: I'm using a [Powershell wrapper](https://pwshspectreconsole.com/) here, but the implementation is more or less the same)

This first example doesn't work, but would be awesome if it did.

```powershell
using namespace Spectre.Console
$data = @(
    @{ Label = "Oranges"; Value = 10; Color = [Color]::new("#3E85ED")},
    @{ Label = "Apples"; Value = 7; Color = [Color]::new("#3EEDBF")},
    @{ Label = "Blueberries"; Value = 3; Color = [Color]::new("#ED6E3E")}
)
Format-SpectreBarChart -Data $data -Title "[white]Fruit Sales[/]" -Width 80
```
This, of course, works:

```powershell
using namespace Spectre.Console
$data = @(
    @{ Label = "Oranges"; Value = 10; Color = [Color]::new(245,137,57)},
    @{ Label = "Apples"; Value = 7; Color = [Color]::new(255,75,138)},
    @{ Label = "Blueberries"; Value = 3; Color = [Color]::new(91,82,238)}
)
Format-SpectreBarChart -Data $data -Title "[white]Fruit Sales[/]" -Width 80
```
![Code_T5qn7J1NlF](https://github.com/spectreconsole/spectre.console/assets/33441569/da68e572-b177-4251-a7f2-098f263b4993)

The way the BarChart is instantiated / created doesn't involve markup - so I can't use Hex. Hopefully all of this is clear.

Really appreciate the hard work, and any consideration on this improvement.

---
Please upvote :+1: this issue if you are interested in it.

### Additional contract requirements

`Color.FromHex(string hex)` creates a `Color` from a six-digit hexadecimal RGB value in `#RRGGBB` form. The returned color represents the supplied red, green, and blue components.
