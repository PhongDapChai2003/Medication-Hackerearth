import shutil
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "audio_sources" / "medicine_bottle_shake_original.wav"
CLEAN_SOURCE = ROOT / "audio_sources" / "medicine_bottle_shake_clean.wav"
DESTINATIONS = [
    ROOT / "ios" / "Runner" / "medicine_bottle_shake.wav",
    ROOT / "macos" / "Runner" / "medicine_bottle_shake.wav",
    ROOT
    / "android"
    / "app"
    / "src"
    / "main"
    / "res"
    / "raw"
    / "medicine_bottle_shake.wav",
]


def read_wave(path: Path) -> tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as source:
        if source.getnchannels() != 1 or source.getsampwidth() != 2:
            raise ValueError("Expected 16-bit mono WAV input")
        sample_rate = source.getframerate()
        samples = np.frombuffer(
            source.readframes(source.getnframes()), dtype="<i2"
        ).astype(np.float64)
    return sample_rate, samples / 32768.0


def high_pass(samples: np.ndarray, sample_rate: int, cutoff: float) -> np.ndarray:
    interval = 1.0 / sample_rate
    rc = 1.0 / (2.0 * np.pi * cutoff)
    alpha = rc / (rc + interval)
    output = np.zeros_like(samples)
    for index in range(1, len(samples)):
        output[index] = alpha * (
            output[index - 1] + samples[index] - samples[index - 1]
        )
    return output


def low_pass(samples: np.ndarray, sample_rate: int, cutoff: float) -> np.ndarray:
    interval = 1.0 / sample_rate
    rc = 1.0 / (2.0 * np.pi * cutoff)
    alpha = interval / (rc + interval)
    output = np.zeros_like(samples)
    output[0] = samples[0]
    for index in range(1, len(samples)):
        output[index] = output[index - 1] + alpha * (
            samples[index] - output[index - 1]
        )
    return output


def frame_spectra(samples: np.ndarray, frame_size: int, hop: int) -> np.ndarray:
    window = np.hanning(frame_size)
    frame_count = max(1, 1 + (len(samples) - frame_size) // hop)
    return np.stack(
        [
            np.abs(np.fft.rfft(samples[index * hop : index * hop + frame_size] * window))
            for index in range(frame_count)
        ]
    )


def spectral_gate(
    samples: np.ndarray,
    noise_profile: np.ndarray,
    frame_size: int = 1024,
    hop: int = 256,
) -> np.ndarray:
    window = np.hanning(frame_size)
    padded_length = frame_size + hop * int(
        np.ceil(max(0, len(samples) - frame_size) / hop)
    )
    padded = np.pad(samples, (0, padded_length - len(samples)))
    output = np.zeros_like(padded)
    weight = np.zeros_like(padded)

    for offset in range(0, len(padded) - frame_size + 1, hop):
        frame = padded[offset : offset + frame_size] * window
        spectrum = np.fft.rfft(frame)
        magnitude = np.abs(spectrum)
        signal_ratio = magnitude / (noise_profile + 1e-10)
        gain = np.clip(1.0 - (1.35 / np.maximum(signal_ratio, 1e-10)), 0.08, 1.0)
        gain = np.convolve(gain, np.ones(5) / 5, mode="same")
        cleaned = np.fft.irfft(spectrum * gain, frame_size)
        output[offset : offset + frame_size] += cleaned * window
        weight[offset : offset + frame_size] += window**2

    valid = weight > 1e-8
    output[valid] /= weight[valid]
    return output[: len(samples)]


def write_wave(path: Path, sample_rate: int, samples: np.ndarray) -> None:
    pcm = np.round(np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as destination:
        destination.setnchannels(1)
        destination.setsampwidth(2)
        destination.setframerate(sample_rate)
        destination.writeframes(pcm.tobytes())


sample_rate, original = read_wave(SOURCE)
filtered = low_pass(high_pass(original, sample_rate, 140.0), sample_rate, 10000.0)

# The actual bottle shakes are concentrated in this interval. Removing the
# long room-noise lead-in and tail makes the notification shorter and clearer.
start = int(0.54 * sample_rate)
end = int(1.63 * sample_rate)
shake = filtered[start:end].copy()

noise_segment = filtered[: int(0.45 * sample_rate)]
noise_spectra = frame_spectra(noise_segment, frame_size=1024, hop=256)
noise_profile = np.median(noise_spectra, axis=0)
cleaned = spectral_gate(shake, noise_profile)

fade_length = int(0.035 * sample_rate)
fade = np.sin(np.linspace(0.0, np.pi / 2.0, fade_length)) ** 2
cleaned[:fade_length] *= fade
cleaned[-fade_length:] *= fade[::-1]

peak = float(np.max(np.abs(cleaned)))
if peak > 0:
    cleaned *= 0.78 / peak

write_wave(CLEAN_SOURCE, sample_rate, cleaned)
for destination in DESTINATIONS:
    shutil.copyfile(CLEAN_SOURCE, destination)

print(f"Created {CLEAN_SOURCE.name}: {len(cleaned) / sample_rate:.2f}s, peak 0.78")
