"""Distribution invariants; never opens personal Pulse data."""
from pathlib import Path
import plistlib
import re
import sys

root = Path(__file__).resolve().parents[1]
for source in (root / 'Sources/Pulse').glob('*.swift'):
    for number, line in enumerate(source.read_text().splitlines(), 1):
        if re.search(r'\b(print|debugLog|ksLog|log)\(', line):
            assert not re.search(r'\\\((?:String\()?\s*(?:text|fullText|final|verify|oldSuffix|newSuffix|char|appName)\b(?!\.count)', line), f'Private content in diagnostic: {source.name}:{number}'
plist = plistlib.loads((root / 'Resources/Info.plist').read_bytes())
assert plist['CFBundleIdentifier'] == 'com.marcofassa.pulse'
assert plist['LSMinimumSystemVersion'] == '26.0'
if len(sys.argv) > 1:
    app = Path(sys.argv[1])
    allowed = {'Contents/Info.plist', 'Contents/MacOS/Pulse', 'Contents/Resources/AppIcon.icns', 'Contents/Resources/StatusBarIcon.png', 'Contents/Resources/StatusBarIcon@2x.png', 'Contents/Resources/StatusIcon.png', 'Contents/Resources/sounds/Start1.wav', 'Contents/Resources/sounds/Stop1.wav', 'Contents/Resources/sounds/noResult1.wav', 'Contents/_CodeSignature/CodeResources'}
    actual = {str(p.relative_to(app)) for p in app.rglob('*') if p.is_file()}
    assert actual <= allowed, f'Unexpected bundle files: {actual-allowed}'
    assert allowed - {'Contents/_CodeSignature/CodeResources'} <= actual, 'Missing bundle files'
    assert plistlib.loads((app/'Contents/Info.plist').read_bytes()) == plist
    binary = (app/'Contents/MacOS/Pulse').read_bytes()
    assert b'/Users/' not in binary, 'Personal build path embedded'
print('Distribution checks passed')
