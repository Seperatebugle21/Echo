"""Seed only the disposable CI simulator's Documents folder for Home screenshots."""
import base64
import datetime
import json
import plistlib
from pathlib import Path
import struct
import sys
import uuid
import wave
import zlib

container = Path(sys.argv[1])
documents = container / 'Documents'
documents.mkdir(parents=True, exist_ok=True)
now = (datetime.datetime.now(datetime.timezone.utc) - datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)).total_seconds()

def artwork(index):
    palettes = [(224, 38, 49), (216, 174, 74), (45, 91, 107), (101, 69, 97), (54, 89, 74)]
    r, g, b = palettes[index % len(palettes)]
    rows = []
    for y in range(256):
        row = bytearray([0])
        for x in range(256):
            shade = 0.3 + 0.7 * (x + 256 - y) / 512
            # Geometric test covers; no external artwork or network dependency.
            mark = ((x - 128) ** 2 + (y - 128) ** 2 < (45 + index * 3) ** 2)
            row.extend((int(r * shade), int(g * shade), int(b * shade), 255) if not mark else (235, 223, 196, 255))
        rows.append(bytes(row))
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 256, 256, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND', b'')

songs = []
for index in range(20):
    filename = f'home-preview-{index}.wav'
    with wave.open(str(documents / filename), 'wb') as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(22050)
        audio.writeframes(b'\0\0' * 22050 * 120)
    songs.append({
        'id': str(uuid.uuid5(uuid.NAMESPACE_URL, f'echo-home-preview-{index}')).upper(),
        'title': ['Morning light', 'After the rain', 'Open road', 'Midnight radio', 'A quieter place'][index % 5] + (f' {index // 5 + 1}' if index >= 5 else ''),
        'artist': ['The North', 'City Lights', 'Sunday Club', 'Red Horizon', 'Slow Seasons'][index % 5],
        'fileName': filename,
        'album': f'Preview album {index % 5 + 1}',
        'coverData': base64.b64encode(artwork(index % 5)).decode(),
        'dateAdded': now - index * 3600,
        'lastPlayed': now - (index + 1) * 3600 if index < 5 else now - 40 * 24 * 3600 if index < 12 else None,
        'tagsInspected': True,
    })
# Optional Codable dates must be omitted instead of null when using this fixture.
for song in songs:
    if song['lastPlayed'] is None:
        del song['lastPlayed']
(documents / 'EchoSongs.json').write_text(json.dumps(songs))
preferences = container / 'Library' / 'Preferences' / 'com.echomusic.app.plist'
preferences.parent.mkdir(parents=True, exist_ok=True)
values = plistlib.loads(preferences.read_bytes()) if preferences.exists() else {}
values['EchoFavorites'] = json.dumps([song['id'] for song in songs[:4]]).encode()
values['EchoPlaylists'] = json.dumps([
    {'id': str(uuid.uuid4()).upper(), 'name': f'Preview mix {index + 1}', 'songIDs': [song['id'] for song in songs[index::4]]}
    for index in range(4)
]).encode()
preferences.write_bytes(plistlib.dumps(values))
print('Seeded 20 test tracks in the disposable simulator.')
