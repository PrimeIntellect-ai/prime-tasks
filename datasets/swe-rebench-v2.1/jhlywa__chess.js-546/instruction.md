.fen({ forceEnpassantSquare = true)) not working
```typescript
import {Chess} from 'chess.js'

const chess = new Chess()


chess.move("h2h4");

console.log(chess.fen({forceEnpassantSquare: true}));
// returns:
// rnbqkbnr/pppppppp/8/8/7P/8/PPPPPPP1/RNBQKBNR b KQkq - 0 1
// expected
// rnbqkbnr/pppppppp/8/8/7P/8/PPPPPPP1/RNBQKBNR b KQkq h3 0 1
```
