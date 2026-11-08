Fix ExtendSectorExpiration to actually update the expiration queue
Sectors are expired according to registration in the `SectorExpirations` queue. The `ExtendSectorExpiration` method doesn't change this, so the sector will expire at its original expiration anyway.

The expiration is redundantly represented in two places, leading to this error. Consider removing the expiration from the sector info, although this might make inspection of sector committed lifetimes a bit more difficult.

See also #394 and #430
