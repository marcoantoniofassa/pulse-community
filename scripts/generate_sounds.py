"""Original Pulse tones, synthesized without samples. Run with Python 3."""
import math
import struct
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'Resources/sounds'
root.mkdir(parents=True, exist_ok=True)
for name, notes in {'Start1': [440, 660], 'Stop1': [660, 440], 'noResult1': [330, 294]}.items():
    frames = bytearray()
    for frequency in notes:
        count = 4800
        for i in range(count):
            envelope = math.sin(math.pi*i/(count-1))**2
            sample = int(6000*envelope*math.sin(2*math.pi*frequency*i/48000))
            frames.extend(struct.pack('<h', sample))
    with wave.open(str(root / f'{name}.wav'), 'wb') as audio:
        audio.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
        audio.writeframes(frames)
    assert len(frames) == 19200
print('Three original tones generated')
