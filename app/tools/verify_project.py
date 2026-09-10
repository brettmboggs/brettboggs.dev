#!/usr/bin/env python3
"""Structural check on the generated project.

There is no Xcode here to open the thing, so this verifies what can be verified
offline: every referenced object exists, every file reference resolves to a real
file on disk, and the target's source list matches the folder it owns.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = "Nightjar"
WIDGET = "SlumbioWidgets"
SOURCE_ROOTS = (APP, WIDGET)
PBXPROJ = ROOT / f"{APP}.xcodeproj/project.pbxproj"

text = PBXPROJ.read_text()
problems: list[str] = []

defined = set(re.findall(r"^\t\t([0-9A-F]{24})[^=]*= \{", text, re.MULTILINE))
referenced = set(re.findall(r"\b([0-9A-F]{24})\b", text))

dangling = referenced - defined
if dangling:
    problems.append(f"referenced but never defined: {sorted(dangling)}")

for uuid in sorted(defined):
    if text.count(uuid) < 2:
        problems.append(f"object {uuid} is declared but never referenced")

# --- File references must resolve on disk ------------------------------------
groups: dict[str, dict] = {}
for match in re.finditer(
    r"^\t\t([0-9A-F]{24})[^=]*= \{\n\t\t\tisa = PBXGroup;\n"
    r"\t\t\tchildren = \(((?:[^)]*?))\n\t\t\t\);\n"
    r"(?:\t\t\tpath = ([^;]+);\n)?(?:\t\t\tname = ([^;]+);\n)?",
    text,
    re.MULTILINE,
):
    uuid, children, path, name = match.groups()
    kids = re.findall(r"([0-9A-F]{24})", children or "")
    groups[uuid] = {
        "children": kids,
        "path": (path or "").strip('"') if path else None,
    }

file_paths: dict[str, str] = {}
for match in re.finditer(
    r"^\t\t([0-9A-F]{24})[^=]*= \{isa = PBXFileReference;[^}]*?path = ([^;]+);",
    text,
    re.MULTILINE,
):
    file_paths[match.group(1)] = match.group(2).strip().strip('"')

resolved: dict[str, Path] = {}


def walk(group_uuid: str, prefix: Path):
    group = groups.get(group_uuid)
    if group is None:
        return
    here = prefix / group["path"] if group["path"] else prefix
    for child in group["children"]:
        if child in groups:
            walk(child, here)
        elif child in file_paths:
            resolved[child] = here / file_paths[child]


main_group = re.search(r"mainGroup = ([0-9A-F]{24});", text)
if not main_group:
    problems.append("no mainGroup")
else:
    walk(main_group.group(1), ROOT)

for uuid, path in resolved.items():
    # Products live in BUILT_PRODUCTS_DIR, not on disk until something builds.
    if path.name.endswith((".app", ".appex")):
        continue
    if not path.exists():
        problems.append(f"file reference does not exist on disk: {path.relative_to(ROOT)}")

# --- Every source on disk belongs to exactly one target ----------------------
# Two targets now, so this is the union of both Sources phases against the union
# of both folders. A file that lands in neither, or in both, is the bug this
# catches.
phases = re.findall(
    r"isa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(((?:[^)]*?))\n\t\t\t\);",
    text,
)
if len(phases) != len(SOURCE_ROOTS):
    problems.append(f"expected {len(SOURCE_ROOTS)} Sources build phases, found {len(phases)}")

in_phase: list[str] = []
for block in phases:
    for build_file in re.findall(r"([0-9A-F]{24})", block):
        ref = re.search(rf"^\t\t{build_file}[^=]*= \{{isa = PBXBuildFile; fileRef = ([0-9A-F]{{24}})", text, re.MULTILINE)
        if ref and ref.group(1) in resolved:
            in_phase.append(str(resolved[ref.group(1)].relative_to(ROOT)))

duplicated = {name for name in in_phase if in_phase.count(name) > 1}
if duplicated:
    problems.append(f"sources compiled into more than one target: {sorted(duplicated)}")
in_phase: set[str] = set(in_phase)

on_disk = set()
for pattern in ("*.swift", "*.metal"):
    for root in SOURCE_ROOTS:
        on_disk |= {str(p.relative_to(ROOT)) for p in (ROOT / root).rglob(pattern)}

missing = on_disk - in_phase
extra = in_phase - on_disk
if missing:
    problems.append(f"sources on disk but in no target: {sorted(missing)}")
if extra:
    problems.append(f"sources in a target but not on disk: {sorted(extra)}")

if problems:
    for problem in problems:
        print("PROBLEM:", problem)
    sys.exit(1)

print(f"project OK: {len(defined)} objects, {len(in_phase)} sources")
