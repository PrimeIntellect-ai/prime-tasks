elastic_ecs module raises spurious exception for STIX 2.1 results
**Describe the bug**
When you set the `"stix_2.1": True` option, you get a bogus exception:
> RuntimeError: Incorrect number of result objects after translation. Found: 23, expected: 2.

[HIDDEN]

Afer doing some grep'ing, I think the proofpoint connector has the same problem.

**To Reproduce**
```
python main.py -d execute elastic_ecs elastic_ecs:beats '{"type":"identity","name":"test","id":"identity--8334a815-a920-4ac8-8168-51aa3755b337"}' '{"host":"example.com","port":9200,"indices":"winlogbeat-*","selfSignedCert": false, "options": {"stix_2.1": true}}' '{"auth":{"id":"my-id","api_key":"my-key"}}' "[process:command_line LIKE '%wmiprvse.exe%'] START t'2022-05-14T00:00:00Z' STOP t'2022-05-15T00:00:00Z'"
```

**Expected behavior**
It should not raise any exceptions.

**Screenshots**
```
 2023-01-30 14:33:44,557 stix_shifter_utils.stix_translation.stix_translation_error_mapper ERROR    received exception => RuntimeError: Incorrect number of result objects after translation. Found: 23, expected: 2.
 2023-01-30 14:33:44,557 stix_shifter_utils.stix_translation.stix_translation_error_mapper DEBUG      File "/home/pcoccoli/github/stix-shifter/main.py", line 4, in <module>
    main()
  File "/home/pcoccoli/github/stix-shifter/stix_shifter/scripts/stix_shifter.py", line 305, in main
    result = translation.translate(args.module, 'results', args.data_source, json.dumps(results), translation_options)
  File "/home/pcoccoli/github/stix-shifter/stix_shifter/stix_translation/stix_translation.py", line 138, in translate
    return entry_point.translate_results(data_source, data)
  File "/home/pcoccoli/github/stix-shifter/stix_shifter_utils/utils/base_entry_point.py", line 68, in wrapper_func
    return func(self, *args, **kwargs)
  File "/home/pcoccoli/github/stix-shifter/stix_shifter_utils/utils/base_entry_point.py", line 179, in translate_results
    ErrorResponder.fill_error(result, message_struct={'exception': ex})
  File "/home/pcoccoli/github/stix-shifter/stix_shifter_utils/utils/error_response.py", line 117, in fill_error
    ErrorResponder.call_module_error_mapper(message_struct, return_object, connector)
  File "/home/pcoccoli/github/stix-shifter/stix_shifter_utils/utils/base_entry_point.py", line 176, in translate_results
    return translator.translate_results(data_source, data)
  File "/home/pcoccoli/github/stix-shifter/stix_shifter_modules/elastic_ecs/stix_translation/results_translator.py", line 38, in translate_results
    [HIDDEN]

  <class 'RuntimeError'> Incorrect number of result objects after translation. Found: 23, expected: 2.
```

**Additional context**
git commit a9e5b43
