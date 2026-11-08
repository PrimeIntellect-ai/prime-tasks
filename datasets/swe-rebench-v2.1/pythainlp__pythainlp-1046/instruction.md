bug: tone_detector wrongly detect falling tone for ครับ
### Description

`print(tone_detector("ครับ"))`
result: f

`print(tone_detector("ค่ะ"))`
result: h

### Expected results

"ครับ" should be high tone
"ค่ะ" should be falling tone

### Current results

"ครับ": falling tone
"ค่ะ": high tone

### Steps to reproduce

`print(tone_detector("ครับ"))`
`print(tone_detector("ค่ะ"))`

### PyThaiNLP version

5.0.4

### Python version

3.10.15

### Operating system and version

macOS 15.1.1

### More info

_No response_

### Possible solution

the falling tone result for "ครับ" is derived from below code block in syllable.py
[HIDDEN]

### Files

_No response_

### Additional contract requirements

- `tone_detector("ครับ")` must return `h` (high tone), and `tone_detector("ค่ะ")` must return `f` (falling tone).
