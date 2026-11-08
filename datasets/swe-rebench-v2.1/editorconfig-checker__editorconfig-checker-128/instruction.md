max_line_length should support non ASCII characters
Currently it seems like `ä`, `ö` and `ü` are counted as two characters which makes the `max_line_length` rule not usable for not plain ASCII files (like UTF-8 so everything with emojis which maybe should also count as one character ;))
