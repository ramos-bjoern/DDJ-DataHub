#!/usr/bin/env python3
"""
Demo-Script: Generiert 1231 zufällige Votes pro Minute gegen die lokale Directus-API.
Aufruf: python3 demo-votes.py
Stoppen: Ctrl+C
"""

import json
import random
import signal
import sys
import time
import urllib.request

API = "http://localhost:8090"
TOKEN = "widget_trikot_2026_readonly"
VOTES_PRO_MINUTE = 1231000
BATCH_SIZE = 100

# Deutschland-Trikots IDs 33–42 mit realistischer Beliebtheitsgewichtung
TRIKOTS = {
    33: (0.05, [0, 0.5, 1, 1, 1.5, 2]),          # 1982
    34: (0.07, [1, 1.5, 2, 2, 2.5, 3]),           # 1986
    35: (0.14, [2.5, 3, 3.5, 4, 4.5, 5]),         # 1990 WM
    36: (0.06, [1, 1.5, 2, 2, 2.5, 3]),           # 1994
    37: (0.05, [0.5, 1, 1.5, 2, 2.5]),            # 1998
    38: (0.09, [2, 2.5, 3, 3.5, 4]),              # 2002
    39: (0.12, [2.5, 3, 3.5, 4, 4.5, 5]),         # 2006 Heim-WM
    40: (0.08, [2, 2.5, 3, 3.5, 4]),              # 2010
    41: (0.29, [3.5, 4, 4, 4.5, 5, 5, 5]),        # 2014 WM
    42: (0.05, [0, 0.5, 1, 1.5, 2]),              # 2018
}

TRIKOT_IDS = list(TRIKOTS.keys())
GEWICHTE = [TRIKOTS[t][0] for t in TRIKOT_IDS]


def zufalls_vote():
    trikot_id = random.choices(TRIKOT_IDS, weights=GEWICHTE)[0]
    bewertung = random.choice(TRIKOTS[trikot_id][1])
    return {"trikot_id": trikot_id, "bewertung": bewertung}


def sende_batch(votes):
    daten = json.dumps(votes).encode()
    req = urllib.request.Request(
        f"{API}/items/trikots_voting",
        data=daten,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())["data"]


def main():
    print(f"╔══════════════════════════════════════════╗")
    print(f"║     DDJ-DataHub — Demo Vote Generator    ║")
    print(f"║     {VOTES_PRO_MINUTE} Votes/Minute · Ctrl+C zum Stoppen ║")
    print(f"╚══════════════════════════════════════════╝")
    print()

    intervall = 60.0 / VOTES_PRO_MINUTE  # Sekunden pro Vote
    batches_pro_minute = VOTES_PRO_MINUTE // BATCH_SIZE
    pause = 60.0 / batches_pro_minute    # Sekunden zwischen Batches

    gesamt = 0
    minute = 1

    signal.signal(signal.SIGINT, lambda *_: (
        print(f"\n\nGestoppt. Gesamt: {gesamt} Votes in {minute-1} Minute(n)."),
        sys.exit(0)
    ))

    while True:
        start = time.time()
        minuten_votes = 0
        print(f"Minute {minute} läuft...", end="", flush=True)

        for _ in range(batches_pro_minute):
            batch = [zufalls_vote() for _ in range(BATCH_SIZE)]
            try:
                result = sende_batch(batch)
                minuten_votes += len(result)
                gesamt += len(result)
                print(f"\r  Minute {minute}: {minuten_votes}/{VOTES_PRO_MINUTE} Votes gesendet  ", end="", flush=True)
            except Exception as e:
                print(f"\n  ⚠ Fehler: {e}")

            # Rest der Batch-Pause abwarten
            vergangen = time.time() - start
            soll = (_ + 1) * pause
            if soll > vergangen:
                time.sleep(soll - vergangen)

        # Restliche Votes in einem letzten Batch
        rest = VOTES_PRO_MINUTE - minuten_votes
        if rest > 0:
            batch = [zufalls_vote() for _ in range(rest)]
            try:
                result = sende_batch(batch)
                minuten_votes += len(result)
                gesamt += len(result)
            except Exception as e:
                print(f"\n  ⚠ Fehler: {e}")

        dauer = time.time() - start
        print(f"\r  ✓ Minute {minute}: {minuten_votes} Votes in {dauer:.1f}s — Gesamt: {gesamt}")
        minute += 1

        # Auf nächste volle Minute warten
        rest_sekunden = 60.0 - (time.time() - start)
        if rest_sekunden > 0:
            time.sleep(rest_sekunden)


if __name__ == "__main__":
    main()
