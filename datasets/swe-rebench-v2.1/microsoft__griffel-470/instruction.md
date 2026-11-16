core: shorthands.gridArea() does not expand custom idents properly
## Outline of issue

In my project I am building graphical dashboard, for the layout of which I am using CSS grid, when using griffel style CSS I have encountered a few problems which I do not get with a traditional CSS file, issues as follows:

- grid template areas, if a element takes up more than 1 template area, this is not reflected in the app only taking up 1 area, the first one it hits
- When using media query with css grid, if the media query is hit to smaller layout then resized to hit larger layout in fast succession grid expands to large width

## Code Example
### Griffel Style
#### Component
```
const useStyles = makeStyles({
    dashboard: {
        display: 'grid',
        width: 'calc(100% - 32px)',
        height: 'calc(100% - 32px )',
        maxWidth: 'calc(100vw - 64px)',
        backgroundColor: tokens.colorNeutralBackground3,
        gridTemplateColumns: '1fr 1fr 1fr',
        gridTemplateRows: '1fr 1fr',
        gridTemplateAreas: `
        "grid1 grid2 grid3"
        "grid4 grid4 grid4"
        `,
        ...shorthands.gap(tokens.spacingHorizontalXXL),
        ...shorthands.padding(tokens.spacingHorizontalL),
        ...shorthands.overflow('auto'),

        '@media (max-width: 1000px)': {
            gridTemplateColumns: '1fr',
            gridTemplateRows: '1fr 1fr 1fr 1fr',
            gridTemplateAreas: `
            "grid1"
            "grid2"
            "grid3"
            "grid4"
            `,
        },
    },
    gridOne: {
        ...shorthands.gridArea('grid1'),
    },
    gridTwo: {
        ...shorthands.gridArea('grid2'),
    },
    gridThree: {
        ...shorthands.gridArea('grid3'),
    },
    gridFour: {
        ...shorthands.gridArea('grid4'),
    },
});
export function MaintenanceDashboard() {
    const styles = useStyles();
    const { t } = useTranslation();
    useWindowTitle(t('maintenance-dashboard.title'));

    return (
        <div className={styles.dashboard}>
            {/* <TasksByDepartment gridPositionClass={'gridOne'} filter="Overdue" />
            <TasksByDepartment gridPositionClass={'gridTwo'} filter="All" />
            <DefectsbyDeptChart gridPostitionClass={'gridThree'} lifeTimeDefects={false} />
            <TradeByDateChart gridPositionClass={'gridFour'} /> */}

            <div className={styles.gridOne} style={{ backgroundColor: 'red' }}>
                grid1
            </div>
            <div className={styles.gridTwo} style={{ backgroundColor: 'red' }}>
                grid2
            </div>
            <div className={styles.gridThree} style={{ backgroundColor: 'red' }}>
                grid3
            </div>
            <div className={styles.gridFour} style={{ backgroundColor: 'red' }}>
                grid4
            </div>
        </div>
    );
}
```

#### Image
![image](https://github.com/microsoft/griffel/assets/117858656/2863ac6c-3c47-4a69-9f29-6ebf060e461b)

### Traditional CSS

#### Component
```
export function MaintenanceDashboard() {
    const styles = useStyles();
    const { t } = useTranslation();
    useWindowTitle(t('maintenance-dashboard.title'));

    return (
        <div className={'dashboard'}>
            <div className={'gridOne'} style={{ backgroundColor: 'red' }}>
                grid1
            </div>
            <div className={'gridTwo'} style={{ backgroundColor: 'red' }}>
                grid2
            </div>
            <div className={'gridThree'} style={{ backgroundColor: 'red' }}>
                grid3
            </div>
            <div className={'gridFour'} style={{ backgroundColor: 'red' }}>
                grid4
            </div>
        </div>
    );
```

### CSS file
```
.dashboard {
    display: grid;
    width: calc(100% - 32px);
    height: calc(100% - 32px);
    max-width: calc(100vw - 64px);
    grid-template-columns: 1fr 1fr 1fr;
    grid-template-rows: 1fr 1fr;
    grid-template-areas:
        'grid1 grid2 grid3'
        'grid4 grid4 grid4';
    gap: 16px;
    padding: 16px;
    overflow: auto;

    @media (max-width: 1000px) {
        grid-template-columns: 1fr;
        grid-template-rows: 1fr 1fr 1fr 1fr;
        grid-template-areas:
            'grid1'
            'grid2'
            'grid3'
            'grid4';
    }
}

.gridOne {
    grid-area: grid1;
}

.gridTwo {
    grid-area: grid2;
}

.gridThree {
    grid-area: grid3;
}

.gridFour {
    grid-area: grid4;
}
````
### Image

![image](https://github.com/microsoft/griffel/assets/117858656/7b477d03-5731-445b-840c-312ea66f9871)

## Version Numbers
@fluentui/react-components: ^9.41.0,
@griffel/react:^1.5.14,
