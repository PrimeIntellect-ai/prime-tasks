Alignment bug?
Hey, I think this should be picked up but its not:

```
  return (
    <P>
      <Clickable inNewTab to={guideUrls[productType]}>
        <Icon className={styles.icon} name="document" size="medium" />Product guide (PDF)
    </Clickable>
    </P>
  );
```
I figure `</Clickable>` should have six spaces behind it.
