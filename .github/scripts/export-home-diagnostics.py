"""Group real XCTest screenshots and accessibility traces into reviewable artifacts."""
import json
import shutil
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:3])
entries = json.loads((source / "manifest.json").read_text())
groups = {"Flow": [], "Vibes": [], "Statistics": [], "Home": []}
for entry in entries:
    identifier = entry["testIdentifier"]
    group = ("Flow" if "testEchoFlow" in identifier else
             "Vibes" if "testSmartVibes" in identifier else
             "Statistics" if "testWeekly" in identifier else "Home")
    groups[group].append(entry)

for group, selected in groups.items():
    if not selected:
        continue
    folder = destination / group
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "manifest.json").write_text(json.dumps(selected, indent=2))
    for entry in selected:
        for attachment in entry["attachments"]:
            name = attachment["exportedFileName"]
            original = source / name
            if original.is_file() and original.suffix.lower() in {".png", ".txt"}:
                shutil.copy2(original, folder / name)
