"""Choisit un simulateur iPhone compatible avec le SDK de Xcode.

Usage : xcrun simctl list devices available -j | python3 pick_simulator.py 18.5
Affiche l'UDID du simulateur choisi.
"""
import json
import re
import sys


def version(runtime):
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)


sdk = tuple(int(part) for part in (sys.argv[1] if len(sys.argv) > 1 else "99.0").split(".")[:2])
devices = json.load(sys.stdin)["devices"]

runtimes = [r for r in devices if "iOS" in r and version(r) <= sdk]
for runtime in sorted(runtimes, key=version, reverse=True):
    phones = [d for d in devices[runtime] if d.get("isAvailable", True) and d["name"].startswith("iPhone")]
    # Un modèle standard (ex. iPhone 16) plutôt qu'un Pro Max, un Plus ou un SE.
    # L'iPhone 15 de l'utilisateur d'abord s'il existe (sinon l'iPhone 16 : même écran 6,1" et Dynamic Island).
    phones.sort(key=lambda d: (any(word in d["name"] for word in ("Pro", "Plus", "SE", "Max")),
                               d["name"] != "iPhone 15", d["name"]))
    if phones:
        print(phones[0]["udid"])
        sys.exit(0)

sys.exit("Aucun simulateur iPhone disponible")
