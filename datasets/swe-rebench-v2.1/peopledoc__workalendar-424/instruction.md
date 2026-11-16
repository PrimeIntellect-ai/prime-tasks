Issue with USA Thanksgiving Friday (Blackfriday) calculation
USA core.py has an issue where Thanksgiving Friday is computed as 4th Friday of November (drawing a parallel from US Thanksgiving which falls on 4th Thursday of November).
While the logic works most of the time, it fails if 1st Nov happens to be a Friday.
Ideally, Thanksgiving Friday should be calculated as a day after Thanksgiving, which is also the definition.
version - master (7.2.0.dev0)
_Though I believe it is platform independent._
I have tried it on Mac OS 10.13 with Python 3.6.5
