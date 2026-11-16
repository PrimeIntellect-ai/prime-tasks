Add support for meta in Spider Contracts
<!--

Thanks for taking an interest in Scrapy!

If you have a question that starts with "How to...", please see the Scrapy Community page: https://scrapy.org/community/.
The GitHub issue tracker's purpose is to deal with bug reports and feature requests for the project itself.

Keep in mind that by filing an issue, you are expected to comply with Scrapy's Code of Conduct, including treating everyone with respect: https://github.com/scrapy/scrapy/blob/master/CODE_OF_CONDUCT.md

The following is a suggested template to structure your pull request, you can find more guidelines at https://doc.scrapy.org/en/latest/contributing.html#writing-patches and https://doc.scrapy.org/en/latest/contributing.html#submitting-patches

-->

## Summary

Today we support `cb_kwargs` but we have scenarios where the data is passed using `meta`.

## Motivation

I have some spiders that use `meta` to store information, e.g: `cookiejar`

## Describe alternatives you've considered

Use callback args.

### Additional contract requirements

Spider contract docstrings can use an `@meta` directive followed by a JSON object. When a contract-generated request is created, its `meta` mapping must contain the entries from that object, allowing its callback to access the supplied metadata.
