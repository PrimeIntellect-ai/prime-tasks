AlphabeticalImports is not working as expected.
This is how my imports are set up in `quicksand` right now [DeleteOldSoftDeletes.php](https://github.com/Jhnbrn90/quicksand/blob/feature/deleting-many-to-many-relationships/src/DeleteOldSoftDeletes.php):

```
use DateInterval;
use DateTime;
use Exception;
use Illuminate\Config\Repository as Config;
use Illuminate\Console\Command;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
```

Tlint should squawk about Log and DB being out of alphabetical order, but running tlint against this file does not catch it.
