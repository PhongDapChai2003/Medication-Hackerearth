import wave

import numpy as np


FILES = [
    "audio_sources/medicine_bottle_shake_original.wav",
    "audio_sources/medicine_bottle_shake_clean.wav",
    "ios/Runner/medicine_bottle_shake.wav",
    "macos/Runner/medicine_bottle_shake.wav",
]


for path in FILES:
    with wave.open(path, "rb") as source:
        samples = np.frombuffer(
            source.readframes(source.getnframes()), dtype="<i2"
        ).astype(float) / 32768
        sample_rate = source.getframerate()

    window = int(0.05 * sample_rate)
    window_rms = np.array(
        [
            np.sqrt(np.mean(samples[index : index + window] ** 2) + 1e-12)
            for index in range(0, len(samples) - window + 1, window)
        ]
    )
    quiet_windows = np.sort(window_rms)[: max(1, len(window_rms) // 4)]

    print(
        path,
        "peak",
        round(float(np.max(np.abs(samples))), 4),
        "rms",
        round(float(np.sqrt(np.mean(samples**2))), 4),
        "quiet_med_db",
        round(float(20 * np.log10(np.median(quiet_windows))), 1),
        "start_db",
        round(
            float(20 * np.log10(np.sqrt(np.mean(samples[:window] ** 2) + 1e-12))),
            1,
        ),
        "end_db",
        round(
            float(20 * np.log10(np.sqrt(np.mean(samples[-window:] ** 2) + 1e-12))),
            1,
        ),
    )
    print(
        "  50ms envelope dB:",
        " ".join(f"{20 * np.log10(value):.0f}" for value in window_rms),
    )
