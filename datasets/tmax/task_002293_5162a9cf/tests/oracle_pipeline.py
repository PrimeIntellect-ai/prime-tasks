import sys
import pandas as pd
import numpy as np
import librosa
from sklearn.preprocessing import StandardScaler

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    input_csv = sys.argv[1]
    output_csv = sys.argv[2]

    df = pd.read_csv(input_csv)

    mfcc_features = []
    for path in df['audio_path']:
        y, sr = librosa.load(path, sr=22050)
        mfccs = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=5, n_fft=2048, hop_length=512)
        mfccs_mean = np.mean(mfccs, axis=1)
        mfcc_features.append(mfccs_mean)

    mfcc_df = pd.DataFrame(mfcc_features, columns=['mfcc0', 'mfcc1', 'mfcc2', 'mfcc3', 'mfcc4'])

    feature_cols = ['f1', 'f2'] + list(mfcc_df.columns)

    df = pd.concat([df.drop('audio_path', axis=1), mfcc_df], axis=1)

    train_idx = df['split'] == 'train'

    scaler = StandardScaler()
    scaler.fit(df.loc[train_idx, feature_cols])

    df[feature_cols] = scaler.transform(df[feature_cols])

    df = df.sort_values('id').reset_index(drop=True)

    for col in feature_cols:
        df[col] = df[col].apply(lambda x: f"{x:.4f}")

    df[['id', 'split', 'f1', 'f2', 'mfcc0', 'mfcc1', 'mfcc2', 'mfcc3', 'mfcc4']].to_csv(output_csv, index=False)

if __name__ == '__main__':
    main()
