import sys
import pandas as pd

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    sensors_path = sys.argv[1]
    preds_path = sys.argv[2]

    sensors = pd.read_csv(sensors_path)
    preds = pd.read_csv(preds_path)

    df = pd.merge(sensors, preds, on='id', how='inner')
    df = df[abs(df['actual_value'] - df['pred_value']) < df['threshold']]
    df = df.sort_values(by='id', ascending=True)
    df = df[['id', 'actual_value', 'pred_value', 'threshold']]

    df.to_csv(sys.stdout, index=False)

if __name__ == '__main__':
    main()
