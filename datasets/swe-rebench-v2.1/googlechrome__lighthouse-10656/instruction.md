The CLI --output csv option should include the requestedUrl in the output.

[batch.txt](https://github.com/GoogleChrome/lighthouse/files/4547869/batch.txt)

[reports.zip](https://github.com/GoogleChrome/lighthouse/files/4547874/reports.zip)

I frequently batch up a number of pages using the CLI, using a command such as:

`lighthouse $page --quiet --output html --output csv --output json --only-categories performance --chrome-flags="--headless"`

This will produce a results with filenames such as www.example.com_2020-04-27_18-34-16.report,csv .json and .html

The reports all just have the domain as the filename. Within the html and json files, I can see what the page I tested was. However with the CSV file the total fields outputted for performance are related to the weightings and don't include the page tested.

There you can see from the attached that the page that was tested is not listed in the CSV, and as the filename doesn't include the page - only the domain - I have to jump through further hoops to compile the data together.

The json output includes, (like the HTML), the actual values rather than a weighting. If all of that could be included in the csv output it would be wonderful - but the page tested fields ("requestedUrl" and "finalUrl") would make the csv much easier to work with at a stroke.

### Additional contract requirements

- The CSV header must be `requestedUrl,finalUrl,category,name,title,type,score`, in that order. Each data row must put its `requestedUrl` and `finalUrl` values in the first two columns, in that order.
