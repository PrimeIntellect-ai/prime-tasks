[BUG] Class of default value may change behavior of repr auto generation
- [x] I've checked [docs](https://rich.readthedocs.io/en/latest/introduction.html) and [closed issues](https://github.com/Textualize/rich/issues?q=is%3Aissue+is%3Aclosed) for possible solutions.
- [x] I can't find my issue in the [FAQ](https://github.com/Textualize/rich/blob/master/FAQ.md).

**Describe the bug**

Thanks for developing rich! I noticed that when automatically generating `__rich_repr__`, parameters are compared to inspects `Parameter.empty` via `==`. For various reasons I use a class which overwrites equality when comparing to `Parameter.empty` and therefore breaks the automatically generated representation.

Here is a minimal working example based on the examples provided in the docs:
```python
import rich
from rich.pretty import pprint
from inspect import Parameter

class StupidClass:
    def __init__(self, a):
        self.a = a

    def __eq__(self, other) -> bool:
        if other is Parameter.empty:
            return True
        try:
            return self.a == other.a
        except Exception:
            return False

    def __ne__(self, other: object) -> bool:
        return not self.__eq__(other)

class NotStupid:
    pass

@rich.repr.auto
class Bird:
    def __init__(self, name, eats, fly=True, another=StupidClass(2), extinct=NotStupid()):
        self.name = name
        self.eats = eats
        self.fly = fly
        self.another = another
        self.extinct = extinct

pprint(Bird("penguin", ["fish"], another=StupidClass(9), extinct=NotStupid()))
```
Output:
```
Bird('penguin', ['fish'], <__main__.StupidClass object at 0x7f8201c35610>, extinct=<__main__.NotStupid object at 0x7f82005ae4f0>)
```

Expected Output:
```
Bird('penguin', ['fish'], another=<__main__.StupidClass object at 0x7fbcc1e44610>, extinct=<__main__.NotStupid object at 0x7fbcc07bd4f0>)
```

**Possible Fix**

[HIDDEN]

**Platform**
<details>
<summary>Click to expand</summary>

What platform (Win/Linux/Mac) are you running on? Ubuntu
 What terminal software are you using? Xfce Terminal Emulator

I may ask you to copy and paste the output of the following commands. It may save some time if you do it now.

If you're using Rich in a terminal:

```
python -m rich diagnose
                                                                                   Rich features

    Colors    ✓ 4-bit color                 ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
              ✓ 8-bit color                 ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
              ✓ Truecolor (16.7 million)    ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
              ✓ Dumb terminals              ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
              ✓ Automatic color conversion  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄

    Styles    All ansi styles: bold, dim, italic, underline, strikethrough, reverse, and even blink.

     Text     Word wrap text. Justify left, center, right or full.

              Lorem ipsum dolor sit amet, consectetur  Lorem ipsum dolor sit amet, consectetur   Lorem ipsum dolor sit amet, consectetur Lorem ipsum dolor  sit  amet,  consectetur
              adipiscing elit. Quisque in metus sed     adipiscing elit. Quisque in metus sed      adipiscing elit. Quisque in metus sed adipiscing  elit.  Quisque  in  metus  sed
              sapien ultricies pretium a at justo.       sapien ultricies pretium a at justo.       sapien ultricies pretium a at justo. sapien  ultricies  pretium  a  at   justo.
              Maecenas luctus velit et auctor maximus. Maecenas luctus velit et auctor maximus. Maecenas luctus velit et auctor maximus. Maecenas luctus velit et auctor maximus.

    Asian     🇨🇳  该库支持中文，日文和韩文文本！
   language   🇯🇵  ライブラリは中国語、日本語、韓国語のテキストをサポートしています
   support    🇰🇷  이 라이브러리는 중국어, 일본어 및 한국어 텍스트를 지원합니다

    Markup    Rich supports a simple bbcode-like markup for color, style, and emoji! 👍 🍎 🐜 🐻 🥖 🚌

    Tables     Date           Title                                 Production Budget       Box Office
              ─────────────────────────────────────────────────────────────────────────────────────────
               Dec 20, 2019   Star Wars: The Rise of Skywalker           $275,000,000     $375,126,118
               May 25, 2018   Solo: A Star Wars Story                    $275,000,000     $393,151,347
               Dec 15, 2017   Star Wars Ep. VIII: The Last Jedi          $262,000,000   $1,332,539,889
               May 19, 1999   Star Wars Ep. I: The phantom Menace        $115,000,000   $1,027,044,677

    Syntax       1 def iter_last(values: Iterable[T]) -> Iterable[Tuple[bool, T]]:                {
 highlighting    2 │   """Iterate and generate a tuple with a flag for last value."""             │   'foo': [3.1427, ('Paul Atreides', 'Vladimir Harkonnen', 'Thufir Hawat')],
      &          3 │   iter_values = iter(values)                                                 │   'atomic': (False, True, None)
    pretty       4 │   try:                                                                       }
   printing      5 │   │   previous_value = next(iter_values)
                 6 │   except StopIteration:
                 7 │   │   return
                 8 │   for value in iter_values:
                 9 │   │   yield False, previous_value
                10 │   │   previous_value = value
                11 │   yield True, previous_value

   Markdown   # Markdown                                                                          ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
                                                                                                  ┃                                   Markdown                                    ┃
              Supports much of the *markdown* __syntax__!                                         ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

              - Headers                                                                           Supports much of the markdown syntax!
              - Basic formatting: **bold**, *italic*, `code`
              - Block quotes                                                                       • Headers
              - Lists, and more...                                                                 • Basic formatting: bold, italic, code
                                                                                                   • Block quotes
                                                                                                   • Lists, and more...

    +more!    Progress bars, columns, styled logging handler, tracebacks, etc...

rendered in 123.0ms (cold cache)
rendered in 50.0ms (warm cache)
                                            ╭────────────────────────────── Thanks for trying out Rich! ───────────────────────────────╮
                                            │                                                                                          │
                                            │  We hope you enjoy using Rich!               Textualize https://github.com/textualize    │
                                            │                                                                                          │
                                            │  Rich is maintained with ❤ by Textualize.io     Twitter https://twitter.com/willmcgugan  │
                                            │                                                                                          │
                                            │  - Will McGugan                                                                          │
                                            │                                                                                          │
                                            ╰──────────────────────────────────────────────────────────────────────────────────────────╯


pip freeze | grep rich
rich==13.3.2
```
</details>

### Additional contract requirements

- In automatic `__rich_repr__` generation, a constructor parameter that has a default must not be treated as required solely because the default object's equality behavior reports it equal to `Parameter.empty`. When its value differs from the declared default, the representation should include the parameter name, as shown for `another` in the reproduction.
