Exporting buttons get dropped
Hey,

Not sure if I am doing this right, but when I set the 'exporting' option they seem to get dropped in the resulting export:

Eg:

    hc_options = {
        'exporting': {
            'buttons': {
                'contextButton': {
                    'enabled': False
                },
                'exportButton': {
                    'text': 'Download',
                    'menuItems': ['downloadPNG']
                }
            }
        }
    }
    chart = Chart(options=hc_options)
    chart.to_json()

Results in this (Notice the menuItems are missing):

{"userOptions": {"exporting": {"buttons": {"contextButton": {"enabled": false}, "exportButton": {"text": "Download"}}}}}

Am I doing it wrong, or is there a problem..?
(Also happens when I try to set the 'onclick' event..

### Additional contract requirements

- The exported JSON produced by ``ExportingButtons.to_json()`` (and by
  ``Chart.to_json()``) must preserve the supplied button configuration for buttons
  defined under any key, not only ``contextButton``. In particular, the ``menuItems``
  list supplied for a button must appear in the resulting export.
- For the example above, the export must contain the ``exportButton`` entry with both
  its ``text`` (``"Download"``) and its ``menuItems`` (``["downloadPNG"]``), and the
  ``contextButton`` entry with ``enabled`` set to ``false``.
