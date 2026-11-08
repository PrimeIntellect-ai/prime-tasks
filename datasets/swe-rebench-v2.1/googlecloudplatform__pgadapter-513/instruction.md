Timestamps with nanosecond precision breaks SQLAlchemy
Timestamps were returned with nanosecond precision in the text format. This could break clients that do not expect this, such as SQLAlchemy.
