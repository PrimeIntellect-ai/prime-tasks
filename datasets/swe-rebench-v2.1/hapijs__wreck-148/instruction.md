process emitter not (reliably) firing handlers
Here's a passing test:

```javascript
    it('clears once handlers from global emitter', (done) => {

        const server = Http.createServer((req, res) => {

            res.writeHead(200);
            res.end('ok');
        });

        let onceHandlerFired = false;
        Wreck.once('request', () => {

            onceHandlerFired = true;
        });


        server.listen(0, () => {

            expect(Wreck.listeners('request').length).to.equal(1);
            Wreck.get('http://localhost:' + server.address().port, (err, res, payload) => {

                expect(err).to.not.exist();
                expect(res.statusCode).to.equal(200);
                expect(payload.toString()).to.equal('ok');
                expect(onceHandlerFired).to.equal(true);
                expect(Wreck.listeners('request').length).to.equal(0);
                server.close();
                done();
            });
        });
    });
```

Following is the exact same test, but instead of adding `request` handlers to `Wreck`, I attempt to add them via `process[Symbol.for('wreck')]`. This version of the test fails, and I would not expect it to:

```javascript
    it('clears once handlers from global emitter', (done) => {

        const wreckEvents = process[Symbol.for('wreck')];
        const server = Http.createServer((req, res) => {

            res.writeHead(200);
            res.end('ok');
        });

        let onceHandlerFired = false;
        wreckEvents.once('request', () => {

            onceHandlerFired = true;
        });


        server.listen(0, () => {

            expect(wreckEvents.listeners('request').length).to.equal(1);
            Wreck.get('http://localhost:' + server.address().port, (err, res, payload) => {

                expect(err).to.not.exist();
                expect(res.statusCode).to.equal(200);
                expect(payload.toString()).to.equal('ok');
                expect(onceHandlerFired).to.equal(true);
                expect(wreckEvents.listeners('request').length).to.equal(0);
                server.close();
                done();
            });
        });
    });
```

I believe this issue is the root cause of joyent/node-consulite#3.
