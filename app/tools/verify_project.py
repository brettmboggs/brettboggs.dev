#!/usr/bin/env python3
"""Structural check on the generated project.

There is no Xcode here to open the thing, so this verifies what can be verified
offline: every referenced object exists, every file reference resolves to a real
file on disk, and each target's source list matches the folders it should own.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "Hush.xcodeproj/project.pbxproj"

text = PBXPROJ.read_text()
problems: list[str] = []

# Objects are declared at the start of a line as "\t\tUUID ... = {".
defined = set(re.findall(r"^\t\t([0-9A-F]{24})[^=]*= \{", text, re.MULTILINE))
referenced = set(re.findall(r"\b([0-9A-F]{24})\b", text))

dangling = referenced - defined
if dangling:
    problems.append(f"referenced but never defined: {sorted(dangling)}")

unused = defined - (referenced - defined)
# Every object except the root should be referenced at least twice (declaration
# plus one use). Count occurrences to find orphans.
for uuid in sorted(defined):
    if text.count(uuid) < 2:
        problems.append(f"object {uuid} is declared but never referenced")

# --- File references must resolve on disk ------------------------------------
# Rebuild the group tree to compute each file's full path.
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

def walk(group_uuid: str, prefix: Path):
    group = groups.get(group_uuid)
    if group is None:
        return
    here = prefix / group["path"] if group["path"] else prefix
    for child in group["children"]:
        if child in groups:
            walk(child, here)
        elif child in file_paths:
            seen_files.add(child)
            resolved = here / file_paths[child]
            # Products live in BUILT_PRODUCTS_DIR, not on disk.
            if resolved.suffix in {".app", ".appex"}:
                continue
            if not (ROOT / resolved).exists():
                problems.append(f"file reference does not exist: {resolved}")

seen_files: set[str] = set()

root_group = re.search(r"mainGroup = ([0-9A-F]{24});", text)
if root_group:
    walk(root_group.group(1), Path("."))
else:
    problems.append("no mainGroup found")

# Every file reference must be reachable from the main group. One that is not
# still compiles, but Xcode cannot resolve its path: it lands in "Recovered
# References" and shows red.
orphans = set(file_paths) - seen_files
for uuid in sorted(orphans):
    name = file_paths[uuid]
    if name.endswith((".app", ".appex")):
        continue
    problems.append(f"file reference is not in any group: {name}")

# --- Target membership --------------------------------------------------------
def sources_for(phase_label: str) -> set[str]:
    """Names of files compiled by the sources phase whose build files carry the label."""
    return set(re.findall(
        r"/\* (.+?) in " + re.escape(phase_label) + r" \*/ = \{isa = PBXBuildFile",
        text,
    ))

app_files = sources_for("Sources-app")
ext_files = sources_for("Sources-ext")

expected_app = {p.name for p in (ROOT / "Hush").rglob("*.swift")} | \
               {p.name for p in (ROOT / "Shared").rglob("*.swift")}
expected_ext = {p.name for p in (ROOT / "HushWidgets").rglob("*.swift")} | \
               {p.name for p in (ROOT / "Shared").rglob("*.swift")}

if app_files != expected_app:
    problems.append(f"app sources mismatch: missing {expected_app - app_files}, extra {app_files - expected_app}")
if ext_files != expected_ext:
    problems.append(f"widget sources mismatch: missing {expected_ext - ext_files}, extra {ext_files - expected_ext}")

# --- Balance -----------------------------------------------------------------
if text.count("{") != text.count("}"):
    problems.append(f"unbalanced braces: {text.count('{')} open, {text.count('}')} close")
if text.count("(") != text.count(")"):
    problems.append(f"unbalanced parens: {text.count('(')} open, {text.count(')')} close")

if problems:
    print("FAILED")
    for problem in problems:
        print("  -", problem)
    sys.exit(1)

print(f"project OK: {len(defined)} objects, "
      f"{len(app_files)} app sources, {len(ext_files)} widget sources")
