BooleanOps creates polygons that are oriented clockwise
Similar to https://github.com/georust/geo/issues/1307, boolean operations in `BooleanOps` such as `intersect` and `union` create polygons whose exterior is oriented **clockwise.** However, "by default, a properly-oriented Polygon has its outer ring oriented counter-clockwise" (doc of module `orient`).

Thus, `BooleanOps` breaks my expectations and I have to `orient` them myself to get the expected results.

Here is a simple unit test to demonstrate the problem

```rust
   #[test]
    fn test_winding_order() {
        let poly1 = polygon!((x: 0.0, y: 0.0), (x: 1.0, y: 0.0), (x: 1.0, y: 1.0));
        assert!(matches!(poly1.exterior().winding_order(), Some(WindingOrder::CounterClockwise)));

        {
            let union = poly1.union(&polygon!());
            assert_eq!(union.0.len(), 1);

            let union = &union.0[0];
            // FAILS
            assert!(matches!(union.exterior().winding_order(), Some(WindingOrder::CounterClockwise)));
        }
        {
            let intersection = poly1.intersection(&poly1);
            assert_eq!(intersection.0.len(), 1);

            let intersection = &intersection.0[0];
            // FAILS
            assert!(matches!(intersection.exterior().winding_order(), Some(WindingOrder::CounterClockwise)));
        }

        let poly2 = polygon!((x: 0.0, y: 0.0), (x: 1.0, y: 1.0), (x: 0.0, y: 1.0));
        assert!(matches!(poly2.exterior().winding_order(), Some(WindingOrder::CounterClockwise)));

        {
            let union = poly1.union(&poly2);
            assert_eq!(union.0.len(), 1);

            let union = &union.0[0];
            assert!(union.interiors().is_empty());
            // FAILS
            assert!(matches!(union.exterior().winding_order(), Some(WindingOrder::CounterClockwise)));
        }
    }
```
