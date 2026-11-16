Rename topen argument with_headers to extract_headers
# Overview

`with_headers` argument is just confusing (based on experience of `jsontableschema.Resource` work) . So it's a part of consistent v1 API work. Changes should be made with adding backward-compatibility code to support `with_headers` argument before v1.
