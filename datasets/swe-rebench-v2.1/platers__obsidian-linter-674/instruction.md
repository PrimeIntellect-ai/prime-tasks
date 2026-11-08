Bug: Add space between CJK & EN Not Ignoring the Ignoring of HTML
```
Before
<u>自己想说的</u>

After
<u> 自己想说的 </u>
```

The underline will contain the extra SPACEs.

### Additional contract requirements

- The “After” sample shows the undesired behavior. HTML markup must not cause the CJK-English spacing rule to insert extra spaces around enclosed CJK text.
