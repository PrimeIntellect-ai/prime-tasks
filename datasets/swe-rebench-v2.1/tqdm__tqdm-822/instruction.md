Use unicodedata.east_asian_width to determine actual width of provided text
Some unicode characters, notably glyphs used in Eastern Asia, are "full-width" and have the property to be rendered in two cells in most terminal emulators. Fortunately, there is a unicode property that specifies its width character and how it is to be rendered in fixed width environments. ([reference](https://en.wikipedia.org/wiki/Halfwidth_and_fullwidth_forms#In_Unicode)) Python's `unicodedata` module has this inside the `unicodedata.east_asian_width` function.

```
$ python --version
Python 3.7.4
$ tqdm --version
4.26.0
$ tqdm --desc "第4話 気づいたんですよね" --total 10
第4話 気づいたんですよね:   0%|                    | 0/10 [00:0
0<?, ?it/s]
```

![2019-09-05_14-38-24](https://user-images.githubusercontent.com/931051/64342480-e0a94f80-cfea-11e9-8f0f-de28e8274cb9.png)

My terminal emulator is alacritty. The issue was also verified in Konsole.

<details>

<summary>Example script illustrating a possible fix</summary>

```py
import unicodedata

tests = [
    "第4話 気づいたんですよね",
    "normal width ASCII text",
    "ｆｕｌｌｗｉｄｔｈ",
    "ニッポン",
    "ﾆｯﾎﾟﾝ",
]

for test in tests:
    print(f"{test} [{len(test)}]")
    [HIDDEN]
    print(f"{'#' * cells} [{cells}]")

    print("".join(map(unicodedata.category, test)))
    print("".join(map(unicodedata.east_asian_width, test)))
    print()
```

```
~ Δ python /tmp/wide_chars.py
第4話 気づいたんですよね [13]
######################## [24]
LoNdLoZsLoLoLoLoLoLoLoLoLo
WNaWNaWWWWWWWWW

normal width ASCII text [23]
####################### [23]
LlLlLlLlLlLlZsLlLlLlLlLlZsLuLuLuLuLuZsLlLlLlLl
NaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNaNa

ｆｕｌｌｗｉｄｔｈ [9]
################## [18]
LlLlLlLlLlLlLlLlLl
FFFFFFFFF

ニッポン [4]
######## [8]
LoLoLoLo
WWWW

ﾆｯﾎﾟﾝ [5]
##### [5]
LoLoLoLmLo
HHHHH
```

![2019-09-05_14-32-14](https://user-images.githubusercontent.com/931051/64342042-fa966280-cfe9-11e9-8d7f-c380e615fe7a.png)


</details>

### Additional contract requirements

- When sizing a progress meter around Unicode text, account for its displayed terminal-cell width rather than its codepoint count. Full-width and wide characters occupy two terminal cells; other characters occupy one, so the bar is sized and aligned to the rendered text.
