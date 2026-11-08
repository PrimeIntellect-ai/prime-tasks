groupby complex attributes
I have a list of objects. These objects have a `date` attribute. I want to group by year.
Something along the lines of the following would be nice.

```
for year, posts in collections.post | groupby("date.year")
```

But it begs the question how to deal with transforms that need to happen before the grouping.
Is there a way to use `groupby` like this?
