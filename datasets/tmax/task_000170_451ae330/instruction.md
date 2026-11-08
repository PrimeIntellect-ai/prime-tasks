You are an automation specialist for a manufacturing plant. Your goal is to build an anomaly detection pipeline that fuses visual sensor data with textual logs. 

Currently, our legacy pipeline fails because it uses basic shell tools that silently drop rows in our metadata logs if they contain embedded newlines. You need to build a robust Python-based pipeline.

You are provided with two inputs:
1. `/app/machine_feed.mp4`: A 60-second, 10 fps video recording of a machine's diagnostic panel.
2. `/app/machine_logs.csv`: A log file with columns `Second`, `Operator`, and `Notes`. Some fields in `Notes` contain embedded newlines.

Your pipeline must perform the following steps:
1. **Frame Extraction & Processing**: Read `/app/machine_feed.mp4`. Convert each frame to grayscale. Calculate the average pixel intensity (0-255) of the top-left 50x50 pixel region for each frame.
2. **Time-based Bucketing**: Aggregate the per-frame intensities into 1-second buckets. Since the video is 10 fps, average the intensities of the 10 frames belonging to each second (0-59).
3. **Log Parsing & Cleansing**: Read `/app/machine_logs.csv` using a robust method that preserves all rows, even those with embedded newlines in the `Notes` field. Strip out the newlines in the parsed data (replace them with spaces).
4. **Changepoint Detection**: For each second (starting from Second 1), mark a changepoint (`True` or `False`) if the absolute difference in average intensity between the current second and the previous second is strictly greater than 15.0. Second 0 is always `False`.
5. **Merging**: Combine the bucketed intensities, changepoint flags, and cleansed logs.

**Output:**
1. Create a CSV file at `/home/user/pipeline_output.csv` with exactly these columns: `Second`, `Mean_Intensity`, `Operator`, `Notes`, `Is_Changepoint`. The file must contain 60 rows of data (plus the header), sorted by `Second` (0 to 59). `Mean_Intensity` should be rounded to 2 decimal places.
2. Create a log file at `/home/user/pipeline.log` that logs the start time, the number of successfully extracted frames, the number of successfully parsed log rows, and the completion time.

Ensure your code is reproducible and cleanly handles the embedded newlines without dropping any logs.