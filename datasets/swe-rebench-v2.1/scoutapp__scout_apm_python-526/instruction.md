Don't log scout key
Currently we log the scout key from configuration and in the register method at startup. Security conscious companies don't want license keys in their log files. We should avoid logging the key, though perhaps a hash or a substring could be useful.
