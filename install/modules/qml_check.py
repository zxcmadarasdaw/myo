#!/usr/bin/env python3
"""Check that every local QML type used by the shell resolves under Quickshell.

    python3 install/modules/qml_check.py [SHELL_DIR] [ENTRY_FILE]

SHELL_DIR defaults to src/quickshell next to this repository, ENTRY_FILE to
Shell.qml. Exit status 1 lists every unresolved type.

Why this is needed: Quickshell loads the config through its own qs: URL
scheme, which Qt treats as a remote location. Qt cannot list a remote
directory, so a QML file only sees the sibling types of its directory when
that directory has a qmldir. Quickshell writes (synthesizes) a qmldir only for
directories its scanner visits: the directory of the entry file, and every
directory reached through `import "dir"` from a scanned file (see
src/core/scan.cpp in Quickshell). A file reached only through a qmldir entry
in another directory (for example `WallpaperEngine 1.0 wallpaper/...` in the
root qmldir) does not make its own directory visible. Its siblings are then
"not a type" and the whole configuration fails to load, although the same
files load fine from file:// URLs (qmlscene, PySide6 tests).

This script repeats that scanner walk and resolves every `Name {` object
declaration whose Name is a local QML type somewhere in the tree.
"""
import os
import re
import sys
from pathlib import Path

IMPORT_RE = re.compile(r'^import\s+"([^"]+)"(?:\s+as\s+(\w+))?')
QS_IMPORT_RE = re.compile(r'^import\s+qs((?:\.\w+)*)(?:\s+as\s+(\w+))?')
OBJECT_RE = re.compile(r'(?<![\w.])(?:(\w+)\.)?([A-Z]\w*)\s*\{')
INLINE_COMPONENT_RE = re.compile(r'\bcomponent\s+([A-Z]\w*)\s*:')
STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')

# Local files whose name is also a Qt/Quickshell type (quickactions/actions/
# Timer.qml): outside their own directory the module type is meant.
BUILTIN_TYPES = {
    "Timer", "Item", "Rectangle", "Text", "Image", "Loader", "Repeater", "Row", "Column",
    "Flow", "Grid", "Canvas", "Shape", "Process", "Connections", "Binding", "Behavior",
    "Component", "QtObject", "Window", "PanelWindow", "PopupWindow", "FileView",
    "Variants", "Scope", "ListView", "GridView", "Flickable", "MouseArea", "Button",
    "Slider", "Switch", "Label", "Icon",
}


def read(path):
    return Path(path).read_text(encoding="utf-8", errors="replace")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    lines = []
    for line in text.split("\n"):
        line = STRING_RE.sub('""', line)
        idx = line.find("//")
        lines.append(line if idx == -1 else line[:idx])
    return "\n".join(lines)


def qmldir_types(path):
    names = set()
    for raw in read(path).splitlines():
        parts = raw.split()
        if not parts or parts[0] in ("module", "plugin", "classname", "typeinfo", "depends",
                                     "import", "designersupported", "optional", "#"):
            continue
        while parts and parts[0] in ("singleton", "internal"):
            parts = parts[1:]
        if len(parts) >= 2 and parts[0][:1].isupper() and parts[-1].endswith(".qml"):
            names.add(parts[0])
    return names


class Scanner:
    """Port of QmlScanner::scanDir/scanQmlFile from Quickshell 0.3."""

    def __init__(self, root):
        self.root = Path(root).resolve()
        self.scanned_files = set()
        self.scanned_dirs = set()
        self.synthesized = {}

    def header_imports(self, path):
        imports = []
        for raw in read(path).splitlines():
            line = raw.strip()
            if line.startswith("import"):
                m = QS_IMPORT_RE.match(line)
                if m and " qs." in line:
                    imports.append(str(self.root.joinpath(*m.group(1).strip(".").split("."))))
                elif '"' in line:
                    start = line.index('"')
                    end = line.find('"', start + 1)
                    if end != -1 and len(line) >= start + 3:
                        imports.append(line[start + 1:end])
            elif "{" in line:
                break
        return imports

    def scan_dir(self, d):
        d = Path(d).resolve()
        if d in self.scanned_dirs:
            return
        self.scanned_dirs.add(d)
        entries = []
        has_qmldir = False
        for name in sorted(os.listdir(d)):
            if not (d / name).is_file():
                continue
            if name == "qmldir":
                has_qmldir = True
            elif name[:1].isupper() and name.endswith(".qml"):
                if self.scan_file(d / name):
                    entries.append(name[:-4])
        if not has_qmldir:
            self.synthesized[d] = set(entries)

    def scan_file(self, path):
        path = Path(path).resolve()
        if path in self.scanned_files:
            return False
        self.scanned_files.add(path)
        current = path.parent
        self.scan_dir(current)
        for imp in self.header_imports(path):
            target = (current / imp).resolve() if not os.path.isabs(imp) else Path(imp)
            if target.is_dir() and not imp.endswith(".js"):
                self.scan_dir(target)
        return True


def check(shell_dir, entry="Shell.qml"):
    root = Path(shell_dir).resolve()
    scanner = Scanner(root)
    scanner.scan_file(root / entry)

    def visible_types(d):
        """Types Qt can see in directory d when it is loaded over qs:."""
        d = Path(d).resolve()
        if (d / "qmldir").is_file():
            return qmldir_types(d / "qmldir")
        return scanner.synthesized.get(d, set())

    qml_files = sorted(p for p in root.rglob("*.qml") if "__pycache__" not in p.parts)
    local_names = {p.stem for p in qml_files if p.stem[:1].isupper()}
    for qd in root.rglob("qmldir"):
        local_names |= qmldir_types(qd)

    problems = []
    for path in qml_files:
        text = read(path)
        code = strip_comments(text)
        unaliased = set(visible_types(path.parent))
        aliased = {}
        for raw in text.splitlines():
            line = raw.strip()
            m = IMPORT_RE.match(line)
            if m:
                imp, alias = m.groups()
                if imp.endswith(".js"):
                    continue
                target = (path.parent / imp).resolve()
                if not target.is_dir():
                    if alias is None:
                        problems.append((path, 0, "import \"%s\" does not exist" % imp))
                    continue
                # An import of a directory without qmldir that Quickshell never
                # scans is not an error by itself; its types are just absent.
                # Missing types are reported where they are used, below.
                types = visible_types(target)
                if alias:
                    aliased.setdefault(alias, set()).update(types)
                else:
                    unaliased |= types
        inline = set(INLINE_COMPONENT_RE.findall(code))
        for lineno, line in enumerate(code.split("\n"), 1):
            for m in OBJECT_RE.finditer(line):
                prefix, name = m.groups()
                if name not in local_names or name in inline:
                    continue
                if name in BUILTIN_TYPES and not prefix:
                    continue
                if prefix and prefix[:1].isupper() and prefix not in aliased:
                    continue  # Qualified Qt type such as Image.Something {
                if prefix and prefix in aliased:
                    if name not in aliased[prefix]:
                        problems.append((path, lineno, "%s.%s is not a type under Quickshell" % (prefix, name)))
                    continue
                if prefix:
                    continue
                if name not in unaliased:
                    problems.append((path, lineno, "%s is not a type under Quickshell (its directory has no qmldir"
                                     " and is not imported anywhere, or it is missing from the imported qmldir)" % name))
    return problems


def main(argv):
    here = Path(__file__).resolve()
    shell_dir = Path(argv[1]) if len(argv) > 1 else here.parents[2] / "src" / "quickshell"
    entry = argv[2] if len(argv) > 2 else "Shell.qml"
    if not (shell_dir / entry).is_file():
        print("qml_check: %s not found" % (shell_dir / entry), file=sys.stderr)
        return 2
    problems = check(shell_dir, entry)
    for path, lineno, message in problems:
        print("%s:%d: %s" % (path.relative_to(shell_dir.resolve()).as_posix(), lineno, message))
    if problems:
        print("qml_check: %d unresolved QML type(s)" % len(problems), file=sys.stderr)
        return 1
    print("qml_check: all local QML types resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
