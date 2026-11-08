Running elements not working with tables
I tried the new running elements feature which seems to be breaking when the running element contains a table.

I used the example from @hbrunn in #882 and added another header:

```html
<html>
    <head>
        <style type="text/css">
            .header {
                position: running(header);
            }
            .footer {
                position: running(footer);
                text-align: center;
            }
            @page {
                @top-center {
                    content: element(header);
                }
                @top-right {
                    content: string(header_string);
                }
                @bottom-center {
                    content: element(footer);
                    /* without this, there's a line break before the pages
                       span
                    */
                    width: 100%;
                }
                @bottom-right {
                    content: counter(page);
                }
            }
            h1 {
                margin-bottom: 15cm;
                string-set: header_string content();
            }
            .page:before {
                content: counter(page);
            }
            .pages:before {
                content: counter(pages);
            }
            .header_string:before {
                content: string(header_string);
            }
        </style>
    </head>
    <body>
        <div class="header">
            Hello world file: <span class="header_string" />
        </div>
        <div class="footer">
            <span class="page" /> of <span class="pages" />
        </div>
        <h1>test1</h1>
        <h1>test2</h1>
        <h1>test3</h1>
        <h1>test4</h1>
        <h1>test5</h1>
        <h1>test6</h1>
        <div class="header">
            <table><tr><td>Hello World</td></tr></table>
        </div>
        <h1>test7</h1>
        <h1>test8</h1>
        <h1>test9</h1>
        <h1>test10</h1>
        <h1>test11</h1>
        <h1>test12</h1>
        <div class="header">
            Hello world2
        </div>
        <h1>test13</h1>
    </body>
</html>
```
This will throw following error:
```
File "/usr/lib/python3.7/site-packages/weasyprint/__init__.py", line 168, in render
    font_config)
  File "/usr/lib/python3.7/site-packages/weasyprint/document.py", line 393, in _render
    [Page(page_box, enable_hinting) for page_box in page_boxes],
  File "/usr/lib/python3.7/site-packages/weasyprint/document.py", line 393, in <listcomp>
    [Page(page_box, enable_hinting) for page_box in page_boxes],
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/__init__.py", line 183, in layout_document
    make_margin_boxes(context, page, state))
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/pages.py", line 435, in make_margin_boxes
    yield margin_box_content_layout(context, page, box)
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/pages.py", line 443, in margin_box_content_layout
    page_is_empty=True, absolute_boxes=[], fixed_boxes=[])
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/blocks.py", line 507, in block_container_layout
    absolute_boxes, fixed_boxes, adjoining_margins)
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/blocks.py", line 63, in block_level_layout
    page_is_empty, absolute_boxes, fixed_boxes, adjoining_margins)
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/blocks.py", line 77, in block_level_layout_switch
    page_is_empty, absolute_boxes, fixed_boxes, adjoining_margins)
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/blocks.py", line 130, in block_box_layout
    absolute_boxes, fixed_boxes, adjoining_margins)
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/blocks.py", line 507, in block_container_layout
    absolute_boxes, fixed_boxes, adjoining_margins)
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/blocks.py", line 63, in block_level_layout
    page_is_empty, absolute_boxes, fixed_boxes, adjoining_margins)
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/blocks.py", line 77, in block_level_layout_switch
    page_is_empty, absolute_boxes, fixed_boxes, adjoining_margins)
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/blocks.py", line 124, in block_box_layout
    context, box, (containing_block.width, containing_block.height))
  File "/usr/lib/python3.7/site-packages/weasyprint/layout/tables.py", line 704, in table_wrapper_width
    table = wrapper.get_wrapped_table()
  File "/usr/lib/python3.7/site-packages/weasyprint/formatting_structure/boxes.py", line 368, in get_wrapped_table
    raise ValueError('Table wrapper without a table')
ValueError: Table wrapper without a table
```

### Additional contract requirements

Running elements are declared with `position: running(<name>)` and inserted
into page margin boxes with `content: element(<name> <keyword>)`. The keyword
selects which assignment of the running element is used:

- `first` (also the default when no keyword is given): the first running
  element assigned on the current page; if no running element is assigned on
  the current page, the last one assigned on the most recent previous page.
- `last`: the last running element assigned on the current page; if no running
  element is assigned on the current page, the last one assigned on the most
  recent previous page.
- `first-except`: nothing if a running element is assigned on the current
  page; otherwise the last one assigned on the most recent previous page.

If no running element with the given name has been assigned on the current or
any previous page, the margin box content is empty.
