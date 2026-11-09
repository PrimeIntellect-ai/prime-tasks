#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        tesseract-ocr \
        tesseract-ocr-rus \
        tesseract-ocr-jpn \
        fonts-noto-cjk \
        fonts-noto-core

    pip3 install pytest pandas pyarrow Pillow python-Levenshtein numpy

    mkdir -p /app /truth

    # Create /app/weather_wide.csv
    cat << 'EOF' > /app/weather_wide.csv
Date,Temp_London,Temp_Moscow,Temp_Tokyo
2023-01-01,6.0,-2.0,10.0
2023-01-02,5.5,-3.0,
2023-01-05,4.0,-5.0,8.0
2023-01-10,3.0,-8.0,5.0
EOF

    # Create /app/aliases.json
    cat << 'EOF' > /app/aliases.json
{
  "London": ["London", "Londres"],
  "Moscow": ["Moscow", "Москва", "Moskau"],
  "Tokyo": ["Tokyo", "東京", "Tokio"]
}
EOF

    # Generate /app/historical_weather.png and /truth/reference.parquet
    python3 -c "
import pandas as pd
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# Generate image
img = Image.new('RGB', (500, 200), color='white')
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc', 24)
except:
    font = ImageFont.load_default()

text = '''Date       City    Temperature
2023-01-04 Mосква  -4.5
2023-01-04 東京    9.2
2023-01-04 London  5.0'''
d.text((20, 20), text, fill=(0,0,0), font=font)
img.save('/app/historical_weather.png')

# Generate reference parquet
data_csv = {
    'Date': pd.to_datetime(['2023-01-01', '2023-01-02', '2023-01-05', '2023-01-10']),
    'Temp_London': [6.0, 5.5, 4.0, 3.0],
    'Temp_Moscow': [-2.0, -3.0, -5.0, -8.0],
    'Temp_Tokyo': [10.0, np.nan, 8.0, 5.0]
}
df_csv = pd.DataFrame(data_csv)
df_long = df_csv.melt(id_vars=['Date'], var_name='City', value_name='Temperature')
df_long['City'] = df_long['City'].str.replace('Temp_', '')

data_ocr = {
    'Date': pd.to_datetime(['2023-01-04']*3),
    'City': ['Moscow', 'Tokyo', 'London'],
    'Temperature': [-4.5, 9.2, 5.0]
}
df_ocr = pd.DataFrame(data_ocr)

df_combined = pd.concat([df_long, df_ocr]).dropna(subset=['Temperature'])
df_combined = df_combined.groupby(['Date', 'City']).mean().reset_index()

df_combined.set_index('Date', inplace=True)
df_resampled = df_combined.groupby('City').resample('D').asfreq()
if 'City' in df_resampled.columns:
    df_resampled = df_resampled.drop(columns=['City'])
df_resampled = df_resampled.reset_index(level='City')
df_resampled['Temperature'] = df_resampled.groupby('City')['Temperature'].transform(lambda x: x.interpolate(method='linear'))
df_resampled = df_resampled.reset_index()

df_resampled = df_resampled[(df_resampled['Date'] >= '2023-01-01') & (df_resampled['Date'] <= '2023-01-10')]
df_resampled = df_resampled.sort_values(['Date', 'City']).reset_index(drop=True)
df_resampled.to_parquet('/truth/reference.parquet')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app /truth /home/user
