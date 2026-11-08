Times not propagated by `.save_to_memory()`
I was a bit surprised to see that the following is possible:

```
rec = si.read_binary_folder(...)
rec1 = rec.save_to_memory()
print(rec.sample_index_to_time(0), rec1.sample_index_to_time(0))
# => 2451.763033333333, 0.0
```

I'm working around this by `rec1.set_times(rec.get_times())`, but it seems to me that since `save()` maintains the times when saving to other formats (like the binary folder), it should do that for memory mode as well.
