bug: Tone detector + syllable sound bug
### Description

Hello, thanks for your work. First and foremost, I am not very skilled in thai, but I think there might be two errors in the functions mentioned above:

1. for `ประ`, `sound_syllable` is returning `live`, but afaik it is dead.
2. for `เอ`, as in the loanword วิตามินเอ, an out of range error is thrown in `tone_detector`. According to http://www.thai-language.com/id/219142 it would be mid tone, so I'd guess middle class consonant, live ending.

```diff
diff --git a/tests/core/test_util.py b/tests/core/test_util.py
index 5d674221..59c647e2 100644
--- a/tests/core/test_util.py
+++ b/tests/core/test_util.py
@@ -680,9 +680,10 @@ class UtilTestCase(unittest.TestCase):
             ("เพราะ", "dead"),
             ("เกาะ", "dead"),
             ("แคะ", "dead"),
+            ("ประ", "dead"),
         ]
         for i, j in test:
-            self.assertEqual(sound_syllable(i), j)
+            self.assertEqual(sound_syllable(i), j, f"{i} should be determined to be a '{j}' syllable.")

     def test_tone_detector(self):
         data = [
@@ -710,9 +711,10 @@ class UtilTestCase(unittest.TestCase):
             ("f", "ผู้"),
             ("h", "ครับ"),
             ("f", "ค่ะ"),
+            ("m", "เอ"), # Pronounciation of the english letter A, as in วิตามินเอ (vitamin A)
         ]
         for i, j in data:
-            self.assertEqual(tone_detector(j), i)
+            self.assertEqual(tone_detector(j), i, f"{j} should be determined to be a '{i}' tone.")

     def test_syllable_length(self):
         self.assertEqual(syllable_length("มาก"), "long")
```

```sh
python -m unittest tests/core/test_util.py
....................F............E.
======================================================================
ERROR: test_tone_detector (tests.core.test_util.UtilTestCase.test_tone_detector)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/tmp/pythainlp/tests/core/test_util.py", line 717, in test_tone_detector
    self.assertEqual(tone_detector(j), i, f"{j} should be determined to be a '{i}' tone.")
                     ~~~~~~~~~~~~~^^^
  File "/tmp/pythainlp/pythainlp/util/syllable.py", line 241, in tone_detector
    s = sound_syllable(syllable)
  File "/tmp/pythainlp/pythainlp/util/syllable.py", line 87, in sound_syllable
    spelling_consonant = consonants[-1]
                         ~~~~~~~~~~^^^^
IndexError: list index out of range

======================================================================
FAIL: test_sound_syllable (tests.core.test_util.UtilTestCase.test_sound_syllable)
----------------------------------------------------------------------
Traceback (most recent call last):
  File "/tmp/pythainlp/tests/core/test_util.py", line 686, in test_sound_syllable
    self.assertEqual(sound_syllable(i), j, f"{i} should be determined to be a '{j}' syllable.")
    ~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError: 'live' != 'dead'
- live
+ dead
 : ประ should be determined to be a 'dead' syllable.

----------------------------------------------------------------------
Ran 35 tests in 1.704s

FAILED (failures=1, errors=1)
```

### Expected results

* ประ is determined as dead syllable
* เอ is determined as mid tone

### Current results

* ประ is determined as live syllable
* เอ throws an error while determining the tone

### Steps to reproduce

`git diff apply` the provided diff and run the unit tests `python -m unittest tests/core/test_util.py`

### PyThaiNLP version

dev

### Python version

3.13.1

### Operating system and version

fedora

### More info

_No response_

### Possible solution

Unfortunately, I don't know.

### Files

_No response_
