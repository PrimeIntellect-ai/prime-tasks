Using  {{statusColor}} does the ID have to be last?
I have a simple query

SELECT

     line_name
     , 1 as color_id
     , line_status_name

FROM
    line_status
    ORDER BY line_name

    This doesn't do a threshold match.

But as soon as I make the ID be last, it starts working.....

SELECT

     line_name
     , line_status_name
     , 1 as color_id

FROM
    line_status
    ORDER BY line_name
