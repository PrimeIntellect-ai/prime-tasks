`nest_joins` only works if `join_prefix` is set
**Describe the bug or question**
Attributes from a joined model are not nested if no `join_prefix` is set

**To Reproduce**

Consider two simple models, `Hero` and `Ability`
```python
class Ability(Base, UUIDMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "abilities"

    name: Mapped[str] = mapped_column(nullable=False)
    strength: Mapped[int] = mapped_column(nullable=False)
    heroes: Mapped[list["Hero"]] = relationship(back_populates="ability")

class Hero(Base, UUIDMixin, TimestampMixin, SoftDeleteMixin):
    __tablename__ = "heroes"

    name: Mapped[str] = mapped_column(nullable=False)
    ability_id: Mapped[int] = mapped_column(ForeignKey("abilities.id"))
    ability: Mapped["Ability"] = relationship(back_populates="heroes")
```

Then, this code does not work as expected:

```python
heroes = await crud_hero.get_multi_joined(db, join_model=Ability, nest_joins=True)
```

Returns this (unrelated columns are removed):

```python
{
    "data": [
        {
            "name": "Diana",
            "ability_id": UUID("6e52176e-8a92-4a8d-b0b3-1fcd55acc666"),
            "id": UUID("8212bccb-ce20-489a-a675-45772ad60eb8"),
            "name_1": "Superstrength",
            "strength": 10,
            "id_1": UUID("6e52176e-8a92-4a8d-b0b3-1fcd55acc666"),
        },
    ],
    "total_count": 2,
}
```

When adding a prefix, it (kinda) works:

```python
heroes = await crud_hero.get_multi_joined(db, join_model=Ability, join_prefix="ability_", nest_joins=True)
```

Result is looking better

```python
{
    "data": [
        {
            "name": "Diana",
            "ability": {
                "id": UUID("6e52176e-8a92-4a8d-b0b3-1fcd55acc666"),
                "name": "Superstrength",
                "strength": 10,
                "id_1": UUID("6e52176e-8a92-4a8d-b0b3-1fcd55acc666"),
            },
            "id": UUID("8212bccb-ce20-489a-a675-45772ad60eb8"),
        },
    ],
    "total_count": 2,
}
```
