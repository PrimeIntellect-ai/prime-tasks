Issue: "Inline" ToDos not captured
Hi @dokato,

Very last thing (promise!) - when checking out the results of the new functionality in #46, I noticed that "inline" comments are not captured by `todor`, e.g. if I have the following text in an Rmarkdown doc on **line 147**:

```
Participants were followed up, and were censored at the earliest of date of diagnosis, death, date of transfer out of the study cohort or end of follow-up ( <!-- TODO Get date here --> )
```

This does not appear as a marker when running `todor()` (no "Line 147"):

![Screenshot 2021-05-13 121403](https://user-images.githubusercontent.com/41202585/118118374-bd9c8900-b3e4-11eb-8aea-709047015be3.jpg)

Is this known behaviour?
