AnyOf["SomeObject", "AnotherObject"] don't work
I tried to specify types via strings but it gives an error.
MRE:
```python
@provide(scope=Scope.REQUEST)
async def new_async_session(
    self, session_factory: async_sessionmaker[AsyncSession]
) -> AsyncIterator[AnyOf["AsyncSession", "UoWProtocol"]]:
    async with session_factory() as session:
        yield session
```
Error:
```dishka.exceptions.GraphMissingFactoryError: Cannot find factory for (<class 'sqlalchemy.ext.asyncio.session.AsyncSession'>, component=''). It is missing or has invalid scope.```
