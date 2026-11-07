#!/usr/bin/env python3
"""Generate the draft contract inventory and R runtime copy; --check detects drift."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
source = root / "spec/summary"
target = root / "inst/schema/summary"
files = {p.name: p for p in source.iterdir() if p.name != "compatibility.json"}
files.update({name: root / "conformance/summary" / name
              for name in ("cases.json", "descriptor.json", "summaries.csv", "roundtrip.csv")})
manifest = {
    "contract": "nftab-summary", "version": "0.1.0", "status": "draft",
    "components": {"intervals": "0.1.0", "summary": "0.1.0", "plot": "0.1.0"},
    "schema_dialect": "draft-07", "nftab_embedding": "0.1.0",
    "calculator_profiles": [],
    "files": {name: hashlib.sha256(p.read_bytes()).hexdigest()
              for name, p in sorted(files.items())},
}
manifest_bytes = (json.dumps(manifest, indent=2) + "\n").encode()
writes = {source / "compatibility.json": manifest_bytes,
          target / "compatibility.json": manifest_bytes}
writes.update({target / name: p.read_bytes() for name, p in files.items()})
if "--check" in sys.argv:
    bad = [str(p.relative_to(root)) for p, data in writes.items()
           if not p.exists() or p.read_bytes() != data]
    if bad:
        raise SystemExit("Contract drift: " + ", ".join(bad))
    print("Contract inventory and runtime copies match.")
else:
    for p, data in writes.items():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    print("Generated draft inventory and runtime copies.")
