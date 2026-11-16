Remove top-level reactor imports from CrawlerProces/CrawlerRunner examples
There are several code examples on https://docs.scrapy.org/en/latest/topics/practices.html that have a top-level `from twisted.internet import reactor`, which is problematic (breaks when the settings specify a non-default reactor) and needs to be fixed.
