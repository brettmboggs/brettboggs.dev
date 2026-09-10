#!/usr/bin/env python3
"""Writes a plausible fortnight into a simulator's container.

Store screenshots of an app with no data in it show empty states, which is
both unflattering and a lie about what the app looks like in use. This writes
the same twelve nights every time, so the set is reproducible.
"""
import json, os, random, sys, uuid
from datetime import datetime, timedelta

MIXES = ["Long Rain", "Long Rain", "Long Rain", "Deep Brown", "Long Rain",
         "Coastline", "Long Rain", "Deep Brown", "Long Rain", "Long Rain",
         "Coastline", "Long Rain"]
SKIPPED = {4, 9}   # two nights missed, because nobody has a clean streak

SETTINGS = {
    "alarmEnabled": True,
    "alarmMinuteOfDay": 6 * 60 + 40,
    "bedtimeReminderEnabled": True,
    "windDownEnabled": True,
    "timerEndAction": "keepPlaying",
    "nightsCompleted": 12,
    "hasOnboarded": True,
    "favouriteSoundIDs": ["light-rain", "campfire", "open-wind"],
}


def main(container):
    directory = os.path.join(container, "Library/Application Support/Nightjar")
    os.makedirs(directory, exist_ok=True)

    random.seed(7)
    now = datetime.now().astimezone()
    sessions = []
    for offset in range(14):
        if offset in SKIPPED:
            continue
        start = (now - timedelta(days=offset + 1)).replace(
            hour=22, minute=random.randint(20, 55), second=0, microsecond=0
        )
        end = start + timedelta(hours=random.uniform(5.6, 8.2))
        sessions.append({
            "id": str(uuid.uuid4()).upper(),
            "start": start.isoformat(timespec="seconds"),
            "end": end.isoformat(timespec="seconds"),
            "mixName": MIXES[offset % len(MIXES)],
            "endedAtAlarm": offset % 3 == 0,
        })
    sessions.sort(key=lambda s: s["start"])
    with open(os.path.join(directory, "journal.json"), "w") as handle:
        json.dump(sessions, handle, indent=2)

    path = os.path.join(directory, "settings.json")
    current = {}
    if os.path.exists(path):
        with open(path) as handle:
            current = json.load(handle)
    current.update(SETTINGS)
    with open(path, "w") as handle:
        json.dump(current, handle, indent=2, sort_keys=True)

    print(f"seeded {len(sessions)} nights")


if __name__ == "__main__":
    main(sys.argv[1])
