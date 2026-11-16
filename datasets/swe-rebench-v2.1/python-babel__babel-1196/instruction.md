Regression in Babel 2.17.0: pybabel extract drops comments for multi-line strings
**Description**
After upgrading to Babel 2.17.0, I noticed that pybabel extract no longer respects translator comments (# NOTE:) when the corresponding translatable string spans multiple lines. This was not an issue in Babel 2.16.0, making this a regression.

**Steps to Reproduce**
Given the following Python code:

```
'test_string': StringWithMeta(
    # NOTE: Text describing a test string
    string=_(
        'Text string that is on a new line'
    ),
),
```

Running pybabel extract with Babel 2.17.0 and the parameter --add-comments='NOTE' results in the .pot file missing the comment, whereas in Babel 2.16.0, the comment is correctly extracted.

**Expected Behavior**
The comment should appear in the .pot file:
```
#. NOTE: Text describing a test string
msgid "Text string that is on a new line"
msgstr ""
```

Actual Behavior (Babel 2.17.0 Output)
```
msgid "Text string that is on a new line"
msgstr ""
```
The # NOTE: comment is missing.

**Additional Findings**
Downgrading to Babel 2.16.0 restores the expected behavior.
This only happens when the string spans multiple lines.
Single-line strings still retain their comments.
