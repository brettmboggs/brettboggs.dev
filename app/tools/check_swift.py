#!/usr/bin/env python3
"""Offline consistency checks for the Swift sources.

There is no Swift compiler in this environment and the iOS SDK does not exist
outside macOS, so the real build happens on someone else's machine. This closes
the gap on the mistakes that are both most likely and most mechanical: calling
one of our own initializers with labels that do not match its declaration, and
overriding a method that no ancestor declares.

It is not a type checker. It only reasons about types declared in this project,
and it stays quiet about anything from a framework.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# --------------------------------------------------------------------------
# Tokenising: strip comments and string bodies so brace and paren matching and
# label extraction never trip over punctuation inside a literal.
# --------------------------------------------------------------------------

def blank_noise(source: str) -> str:
    """Replace comments and string contents with spaces, preserving offsets."""
    out = list(source)
    i, n = 0, len(source)
    while i < n:
        ch = source[i]
        if ch == '/' and i + 1 < n and source[i + 1] == '/':
            while i < n and source[i] != '\n':
                out[i] = ' '
                i += 1
        elif ch == '/' and i + 1 < n and source[i + 1] == '*':
            depth = 1
            out[i] = out[i + 1] = ' '
            i += 2
            while i < n and depth:
                if source.startswith('/*', i):
                    depth += 1
                    out[i] = out[i + 1] = ' '
                    i += 2
                elif source.startswith('*/', i):
                    depth -= 1
                    out[i] = out[i + 1] = ' '
                    i += 2
                else:
                    if source[i] != '\n':
                        out[i] = ' '
                    i += 1
        elif source.startswith('"""', i):
            out[i:i + 3] = '   '
            i += 3
            while i < n and not source.startswith('"""', i):
                if source[i] != '\n':
                    out[i] = ' '
                i += 1
            if i < n:
                out[i:i + 3] = '   '
                i += 3
        elif ch == '"':
            out[i] = ' '
            i += 1
            while i < n and source[i] != '"':
                if source[i] == '\\':
                    out[i] = ' '
                    i += 1
                    if i < n:
                        out[i] = ' '
                        i += 1
                    continue
                if source[i] != '\n':
                    out[i] = ' '
                i += 1
            if i < n:
                out[i] = ' '
                i += 1
        else:
            i += 1
    return ''.join(out)


def match_paren(text: str, open_index: int) -> int:
    """Index of the paren closing the one at `open_index`, or -1."""
    depth = 0
    for i in range(open_index, len(text)):
        c = text[i]
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return i
    return -1


def split_top_level(text: str) -> list[str]:
    """Split an argument list on commas that are not nested."""
    parts, depth, current = [], 0, []
    for c in text:
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        if c == ',' and depth == 0:
            parts.append(''.join(current))
            current = []
        else:
            current.append(c)
    if ''.join(current).strip():
        parts.append(''.join(current))
    return parts


# --------------------------------------------------------------------------
# Declarations
# --------------------------------------------------------------------------

DECL = re.compile(
    r'\b(?:public\s+|private\s+|internal\s+|fileprivate\s+|final\s+|open\s+)*'
    r'(struct|class|enum|extension)\s+([A-Z][A-Za-z0-9_]*)'
)
INIT = re.compile(r'(?<![.\w])(?:public\s+|private\s+|required\s+|convenience\s+)*init\??\s*\(')
STORED = re.compile(
    r'^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?'
    r'((?:@\w+(?:\([^)]*\))?\s+)*)'
    r'(?:private\(set\)\s+)?(var|let)\s+([a-z_][A-Za-z0-9_]*)\s*:\s*([^={\n]+?)\s*(=|$|\{)'
)


class Decl:
    def __init__(self, kind, name):
        self.kind = kind
        self.name = name
        self.inits: list[tuple[list[str], set[str]]] = []  # (labels, defaulted)
        self.stored: list[tuple[str, bool]] = []           # (label, has_default)
        self.superclass: str | None = None
        self.methods: set[str] = set()
        self.overrides: list[tuple[str, str, int]] = []    # (method, file, line)


IDENTIFIER = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def first_top_level_colon(text: str) -> int:
    depth = 0
    for i, c in enumerate(text):
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        elif c == ':' and depth == 0:
            return i
    return -1


def parse_labels(arglist: str) -> tuple[list[str], set[str]]:
    """Declaration parameters: `label name: Type = default`."""
    labels, defaulted = [], set()
    for raw in split_top_level(arglist):
        piece = raw.strip()
        if not piece:
            continue
        colon = first_top_level_colon(piece)
        if colon < 0:
            continue
        names = piece[:colon].split()
        if not names:
            continue
        label = names[0]
        labels.append(label)
        if '=' in piece[colon:]:
            defaulted.add(label)
    return labels, defaulted


def parse_call_labels(arglist: str) -> list[str]:
    """Call arguments: `label: value`, or positional, which reads as `_`."""
    labels = []
    for raw in split_top_level(arglist):
        piece = raw.strip()
        if not piece:
            continue
        colon = first_top_level_colon(piece)
        if colon < 0:
            labels.append('_')
            continue
        head = piece[:colon].strip()
        labels.append(head if IDENTIFIER.match(head) else '_')
    return labels


def collect(files: list[Path]) -> dict[str, Decl]:
    decls: dict[str, Decl] = {}
    for path in files:
        raw = path.read_text()
        clean = blank_noise(raw)
        for m in DECL.finditer(clean):
            kind, name = m.group(1), m.group(2)
            brace = clean.find('{', m.end())
            if brace < 0:
                continue
            end = match_paren(clean, brace)
            if end < 0:
                continue
            body_clean = clean[brace + 1:end]

            decl = decls.setdefault(name, Decl(kind, name))
            if kind != 'extension':
                decl.kind = kind
                # Superclass or first conformance.
                header = clean[m.end():brace]
                if ':' in header:
                    first = header.split(':', 1)[1].split(',')[0]
                    first = first.split('where')[0].strip()
                    if first and first[0].isupper():
                        decl.superclass = first

            depth = 0
            pending_attributes = ''
            for line_no, line in enumerate(body_clean.split('\n')):
                if depth == 0:
                    stripped = line.strip()
                    sm = STORED.match(line)
                    if sm and kind == 'struct' and sm.group(5) != '{':
                        attributes = sm.group(1) + pending_attributes
                        label, type_name = sm.group(3), sm.group(4)
                        # A property wrapper brings its own storage, and an
                        # Optional gets nil from the memberwise initialiser.
                        # @ViewBuilder is neither: it is still required, and is
                        # normally passed as a trailing closure.
                        wrapped = bool(attributes.strip()) and '@ViewBuilder' not in attributes
                        optional = type_name.rstrip().endswith('?')
                        has_default = sm.group(5) == '=' or wrapped or optional
                        decl.stored.append((label, has_default))
                    # An attribute alone on a line applies to the next one.
                    if stripped.startswith('@') and not re.search(r'\b(var|let|func)\b', stripped):
                        pending_attributes += stripped + ' '
                    elif stripped:
                        pending_attributes = ''
                    fm = re.search(r'\bfunc\s+([a-z_][A-Za-z0-9_]*)', line)
                    if fm:
                        if 'override' in line:
                            decl.overrides.append((fm.group(1), str(path), line_no))
                        else:
                            decl.methods.add(fm.group(1))
                depth += line.count('{') - line.count('}')

            for im in INIT.finditer(body_clean):
                close = match_paren(body_clean, im.end() - 1)
                if close < 0:
                    continue
                decl.inits.append(parse_labels(body_clean[im.end():close]))
    return decls


# --------------------------------------------------------------------------
# Call sites
# --------------------------------------------------------------------------

SKIP_CALL_CONTEXT = re.compile(r'(?:func|init|case|\.)\s*$')


def check_calls(files: list[Path], decls: dict[str, Decl]) -> list[str]:
    problems = []
    for path in files:
        raw = path.read_text()
        clean = blank_noise(raw)
        for m in re.finditer(r'\b([A-Z][A-Za-z0-9_]*)\s*\(', clean):
            name = m.group(1)
            decl = decls.get(name)
            if decl is None or decl.kind not in ('struct', 'class'):
                continue
            before = clean[max(0, m.start() - 12):m.start()]
            if SKIP_CALL_CONTEXT.search(before):
                continue

            close = match_paren(clean, m.end() - 1)
            if close < 0:
                continue
            used = parse_call_labels(clean[m.end():close])
            used_set = {u for u in used if u != '_'}

            # Candidate signatures: explicit inits, plus the memberwise one for
            # a struct that declares none.
            candidates: list[tuple[set[str], set[str]]] = []
            for labels, defaulted in decl.inits:
                candidates.append(({l for l in labels if l != '_'}, defaulted))
            if not decl.inits and decl.kind == 'struct' and decl.stored:
                labels = {label for label, _ in decl.stored}
                defaulted = {label for label, has in decl.stored if has}
                candidates.append((labels, defaulted))
            if not candidates:
                continue

            # A trailing closure supplies the last parameter without a label.
            after = clean[close + 1:close + 3]
            trailing = after.lstrip().startswith('{')

            if any(
                used_set <= known and not (known - used_set - defaulted - ({'_'} if trailing else set()))
                or (used_set <= known and (known - used_set - defaulted) and trailing
                    and len(known - used_set - defaulted) <= 1)
                for known, defaulted in candidates
            ):
                continue

            best_known, best_defaulted = candidates[0]
            unknown = used_set - best_known
            line = clean[:m.start()].count('\n') + 1
            rel = path.relative_to(ROOT)
            if unknown:
                problems.append(
                    f"{rel}:{line}: {name}(...) has no parameter "
                    f"{', '.join(sorted(unknown))} "
                    f"(declared: {', '.join(sorted(best_known)) or 'none'})"
                )
            else:
                missing = best_known - used_set - best_defaulted
                if missing and not trailing:
                    problems.append(
                        f"{rel}:{line}: {name}(...) is missing required "
                        f"{', '.join(sorted(missing))}"
                    )
    return problems


def check_numeric_literals(files: list[Path]) -> list[str]:
    """Hex and binary literals with digits outside their base."""
    problems = []
    for path in files:
        clean = blank_noise(path.read_text())
        for m in re.finditer(r'\b0([xXbB])([0-9A-Za-z_]+)', clean):
            base, digits = m.group(1).lower(), m.group(2)
            allowed = '0123456789abcdef_' if base == 'x' else '01_'
            bad = {c for c in digits.lower() if c not in allowed}
            # A float literal like 0x1p3 or a suffix is not our concern here.
            bad -= {'p'}
            if bad:
                line = clean[:m.start()].count('\n') + 1
                problems.append(
                    f"{path.relative_to(ROOT)}:{line}: "
                    f"0{m.group(1)}{digits} is not a valid literal "
                    f"({', '.join(sorted(bad))} out of range)"
                )
    return problems


def check_catalog(files: list[Path]) -> list[str]:
    """Every catalog sound must have a texture, and vice versa.

    A missing case falls through to the factory's default and plays brown
    noise under the wrong name, which no compiler will ever complain about.
    """
    catalog = ROOT / 'Shared/SoundCatalog.swift'
    factory = ROOT / 'Hush/Audio/Textures.swift'
    if not catalog.exists() or not factory.exists():
        return []

    catalog_text = catalog.read_text()
    ids = set(re.findall(r'id: "([^"]+)", name:', catalog_text))
    recordings = set(re.findall(
        r'id: "([^"]+)"[^)]*?source: \.recording', catalog_text, re.S))
    cases = set(re.findall(
        r'case "([^"]+)": return \w+Texture', factory.read_text()))

    problems = []
    for missing in sorted(ids - cases - recordings):
        problems.append(f"catalog sound '{missing}' has no case in TextureFactory")
    for extra in sorted(cases - ids):
        problems.append(f"TextureFactory handles '{extra}', which is not in the catalog")
    return problems


def check_overrides(decls: dict[str, Decl]) -> list[str]:
    problems = []
    for decl in decls.values():
        for method, path, _ in decl.overrides:
            found, cursor, hops = False, decl.superclass, 0
            while cursor and hops < 8:
                parent = decls.get(cursor)
                if parent is None:
                    found = True  # framework superclass, out of scope
                    break
                if method in parent.methods:
                    found = True
                    break
                cursor, hops = parent.superclass, hops + 1
            if not found:
                rel = Path(path).relative_to(ROOT)
                problems.append(
                    f"{rel}: {decl.name}.{method}() is marked override "
                    f"but no ancestor declares it"
                )
    return problems


if __name__ == '__main__':
    files = sorted(
        p for p in ROOT.rglob('*.swift')
        if 'DerivedData' not in p.parts
    )
    decls = collect(files)
    problems = (
        check_calls(files, decls)
        + check_overrides(decls)
        + check_numeric_literals(files)
        + check_catalog(files)
    )

    types = sum(1 for d in decls.values() if d.kind in ('struct', 'class', 'enum'))
    if problems:
        print(f"FAILED ({len(problems)} findings across {len(files)} files)")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print(f"consistency OK: {len(files)} files, {types} types, "
          f"{sum(len(d.inits) for d in decls.values())} initialisers checked")
