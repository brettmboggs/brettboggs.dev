#!/usr/bin/env python3
"""Generates Nightjar.xcodeproj from the source tree.

Hand-maintaining a .pbxproj is miserable and hand-editing one in a diff is
worse, so the project file is generated. Add a Swift or Metal file anywhere
under Nightjar/ and re-run this; membership follows the folder.

    python3 tools/make_project.py

One app target, no extensions, no entitlements. A free Apple ID can sign and
install it; a paid one can ship it. UUIDs are derived from a hash of each
object's role, so regenerating produces a byte-identical file and the project
does not churn in git.
"""
import hashlib
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "Nightjar.xcodeproj"

APP_NAME = "Nightjar"
BUNDLE_ID = "dev.brettboggs.nightjar"
DEPLOYMENT_TARGET = "18.0"
SWIFT_VERSION = "5.0"
MARKETING_VERSION = "1.0"
PROJECT_VERSION = "1"


def development_team() -> str:
    """The Apple team id to sign with, preserved across regeneration.

    Checked in order: an explicit environment override (what CI uses), a
    gitignored Local.xcconfig, then whatever the current project file already
    says, so a team picked in Xcode's Signing pane survives a regeneration.
    """
    override = os.environ.get("NIGHTJAR_TEAM_ID", "").strip()
    if override:
        return override

    local = ROOT / "Local.xcconfig"
    if local.exists():
        found = re.search(r"DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]+)", local.read_text())
        if found:
            return found.group(1)

    existing = PROJECT / "project.pbxproj"
    if existing.exists():
        found = re.search(r"DEVELOPMENT_TEAM = ([A-Z0-9]+);", existing.read_text())
        if found:
            return found.group(1)

    return ""


FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".metal": "sourcecode.metal",
    ".plist": "text.plist.xml",
    ".xcassets": "folder.assetcatalog",
    ".md": "net.daringfireball.markdown",
    ".png": "image.png",
    ".m4a": "file",
    ".xcconfig": "text.xcconfig",
    ".storekit": "text",
}


def uuid_for(key: str) -> str:
    """24 uppercase hex characters, stable for a given key."""
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()


def quote(value: str) -> str:
    if value and all(c.isalnum() or c in "_." for c in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def sources(directory: Path) -> list[Path]:
    found = []
    for pattern in ("*.swift", "*.metal"):
        found += [p.relative_to(ROOT) for p in (ROOT / directory).rglob(pattern)]
    return sorted(found)


class Project:
    def __init__(self):
        self.objects: dict[str, str] = {}

    def add(self, uuid: str, comment: str, isa_body: str):
        label = f" /* {comment} */" if comment else ""
        self.objects[uuid] = f"\t\t{uuid}{label} = {isa_body};"

    def render(self, root_uuid: str) -> str:
        body = "\n".join(self.objects[key] for key in sorted(self.objects))
        return (
            "// !$*UTF8*$!\n"
            "{\n"
            "\tarchiveVersion = 1;\n"
            "\tclasses = {\n"
            "\t};\n"
            "\tobjectVersion = 56;\n"
            "\tobjects = {\n"
            f"{body}\n"
            "\t};\n"
            f"\trootObject = {root_uuid} /* Project object */;\n"
            "}\n"
        )


def build() -> str:
    project = Project()
    team = development_team()

    app_sources = sources(Path(APP_NAME))

    # The asset catalog plus every bundled recording.
    resources = [Path(f"{APP_NAME}/Assets.xcassets")] + [
        path.relative_to(ROOT)
        for path in sorted((ROOT / f"{APP_NAME}/Resources").rglob("*"))
        if path.is_file()
    ]
    support = [
        Path(f"{APP_NAME}/Info.plist"),
        Path("Signing.xcconfig"),
        Path(f"{APP_NAME}.storekit"),
    ]

    all_files = app_sources + resources + support

    # ---- PBXFileReference -------------------------------------------------
    file_refs: dict[str, str] = {}
    for path in all_files:
        ref = uuid_for(f"fileref:{path}")
        file_refs[str(path)] = ref
        kind = FILE_TYPES.get(path.suffix, "text")
        project.add(
            ref,
            path.name,
            "{isa = PBXFileReference; lastKnownFileType = %s; path = %s; sourceTree = \"<group>\"; }"
            % (kind, quote(path.name)),
        )

    app_product = uuid_for("product:app")
    project.add(
        app_product,
        f"{APP_NAME}.app",
        '{isa = PBXFileReference; explicitFileType = wrapper.application; '
        'includeInIndex = 0; path = %s; sourceTree = BUILT_PRODUCTS_DIR; }'
        % quote(f"{APP_NAME}.app"),
    )

    # ---- PBXBuildFile -----------------------------------------------------
    def build_files(paths, target: str) -> list[tuple[str, str]]:
        entries = []
        for path in paths:
            uuid = uuid_for(f"buildfile:{target}:{path}")
            project.add(
                uuid,
                f"{path.name} in {target}",
                "{isa = PBXBuildFile; fileRef = %s /* %s */; }"
                % (file_refs[str(path)], path.name),
            )
            entries.append((uuid, path.name))
        return entries

    source_entries = build_files(app_sources, "Sources")
    resource_entries = build_files(resources, "Resources")

    # ---- Groups -----------------------------------------------------------
    def file_list(entries) -> str:
        if not entries:
            return "(\n\t\t\t)"
        rows = "".join(f"\n\t\t\t\t{uuid} /* {name} */," for uuid, name in entries)
        return "(%s\n\t\t\t)" % rows

    def make_group(uuid: str, name: str, path, children: list[tuple[str, str]]) -> None:
        rows = "".join(f"\n\t\t\t\t{child} /* {label} */," for child, label in children)
        body = [
            "isa = PBXGroup;",
            "children = (%s\n\t\t\t);" % rows,
        ]
        if path is not None:
            body.append(f"path = {quote(path)};")
        elif name:
            body.append(f"name = {quote(name)};")
        body.append('sourceTree = "<group>";')
        project.add(uuid, name, "{\n\t\t\t" + "\n\t\t\t".join(body) + "\n\t\t}")

    def group_tree(directory: Path, files: list[Path]) -> tuple[str, str]:
        """Builds a group mirroring the folder layout under `directory`."""
        uuid = uuid_for(f"group:{directory}")
        direct = sorted([f for f in files if f.parent == directory], key=lambda p: p.name)
        immediate = sorted({
            directory / f.relative_to(directory).parts[0]
            for f in files
            if f.parent != directory and directory in f.parents
        })

        children: list[tuple[str, str]] = []
        for sub in immediate:
            sub_files = [f for f in files if sub == f.parent or sub in f.parents]
            child_uuid, child_name = group_tree(sub, sub_files)
            children.append((child_uuid, child_name))
        for path in direct:
            children.append((file_refs[str(path)], path.name))

        make_group(uuid, directory.name, directory.name, children)
        return uuid, directory.name

    app_files = app_sources + resources + [Path(f"{APP_NAME}/Info.plist")]
    app_group, _ = group_tree(Path(APP_NAME), app_files)

    products_group = uuid_for("group:products")
    make_group(products_group, "Products", None, [(app_product, f"{APP_NAME}.app")])

    main_group = uuid_for("group:main")
    make_group(main_group, "", None, [
        (app_group, APP_NAME),
        (file_refs["Signing.xcconfig"], "Signing.xcconfig"),
        (file_refs[f"{APP_NAME}.storekit"], f"{APP_NAME}.storekit"),
        (products_group, "Products"),
    ])

    # ---- Build phases -----------------------------------------------------
    def phase(uuid: str, isa: str, name: str, entries) -> None:
        project.add(
            uuid,
            name,
            "{\n\t\t\tisa = %s;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = %s;\n"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}"
            % (isa, file_list(entries)),
        )

    sources_phase = uuid_for("phase:app:sources")
    frameworks_phase = uuid_for("phase:app:frameworks")
    resources_phase = uuid_for("phase:app:resources")
    phase(sources_phase, "PBXSourcesBuildPhase", "Sources", source_entries)
    phase(frameworks_phase, "PBXFrameworksBuildPhase", "Frameworks", [])
    phase(resources_phase, "PBXResourcesBuildPhase", "Resources", resource_entries)

    # ---- Build configurations --------------------------------------------
    def settings_block(pairs: dict[str, str]) -> str:
        rows = "".join(f"\n\t\t\t\t{key} = {value};" for key, value in sorted(pairs.items()))
        return "{%s\n\t\t\t}" % rows

    base = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_STRICT_CONCURRENCY": "minimal",
        "SWIFT_VERSION": SWIFT_VERSION,
    }
    debug = dict(base, **{
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": '(\n\t\t\t\t\t"DEBUG=1",\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t)',
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"DEBUG $(inherited)"',
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    })
    release = dict(base, **{
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    })

    app_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": PROJECT_VERSION,
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": f"{APP_NAME}/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    if team:
        app_common["DEVELOPMENT_TEAM"] = team

    signing_ref = file_refs["Signing.xcconfig"]
    configs = {
        "project:Debug": debug,
        "project:Release": release,
        "app:Debug": app_common,
        "app:Release": app_common,
    }
    config_uuids = {}
    for key, values in configs.items():
        name = key.split(":")[1]
        uuid = uuid_for(f"buildconfig:{key}")
        config_uuids[key] = uuid
        base_line = ""
        if key.startswith("app:"):
            base_line = f"\t\t\tbaseConfigurationReference = {signing_ref} /* Signing.xcconfig */;\n"
        project.add(
            uuid,
            name,
            "{\n\t\t\tisa = XCBuildConfiguration;\n"
            f"{base_line}"
            f"\t\t\tbuildSettings = {settings_block(values)};\n"
            f"\t\t\tname = {name};\n\t\t}}",
        )

    def config_list(scope: str, default: str = "Release") -> str:
        uuid = uuid_for(f"configlist:{scope}")
        project.add(
            uuid,
            f"Build configuration list for {scope}",
            "{\n\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            f"\t\t\t\t{config_uuids[f'{scope}:Debug']} /* Debug */,\n"
            f"\t\t\t\t{config_uuids[f'{scope}:Release']} /* Release */,\n"
            "\t\t\t);\n"
            "\t\t\tdefaultConfigurationIsVisible = 0;\n"
            f"\t\t\tdefaultConfigurationName = {default};\n\t\t}}",
        )
        return uuid

    project_config_list = config_list("project")
    app_config_list = config_list("app")

    # ---- Target -----------------------------------------------------------
    project_uuid = uuid_for("project")
    app_target = uuid_for("target:app")
    project.add(
        app_target,
        APP_NAME,
        "{\n\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {app_config_list};\n"
        "\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{sources_phase} /* Sources */,\n"
        f"\t\t\t\t{frameworks_phase} /* Frameworks */,\n"
        f"\t\t\t\t{resources_phase} /* Resources */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n\t\t\t);\n"
        "\t\t\tdependencies = (\n\t\t\t);\n"
        f"\t\t\tname = {APP_NAME};\n"
        f"\t\t\tproductName = {APP_NAME};\n"
        f"\t\t\tproductReference = {app_product} /* {APP_NAME}.app */;\n"
        '\t\t\tproductType = "com.apple.product-type.application";\n\t\t}',
    )

    # ---- Project ----------------------------------------------------------
    project.add(
        project_uuid,
        "Project object",
        "{\n\t\t\tisa = PBXProject;\n"
        "\t\t\tattributes = {\n"
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        "\t\t\t\tLastSwiftUpdateCheck = 1620;\n"
        "\t\t\t\tLastUpgradeCheck = 1620;\n"
        "\t\t\t\tTargetAttributes = {\n"
        f"\t\t\t\t\t{app_target} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.2;\n\t\t\t\t\t}};\n"
        "\t\t\t\t};\n"
        "\t\t\t};\n"
        f"\t\t\tbuildConfigurationList = {project_config_list};\n"
        '\t\t\tcompatibilityVersion = "Xcode 14.0";\n'
        "\t\t\tdevelopmentRegion = en;\n"
        "\t\t\thasScannedForEncodings = 0;\n"
        "\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
        f"\t\t\tmainGroup = {main_group};\n"
        "\t\t\tminimizedProjectReferenceProxies = 1;\n"
        f"\t\t\tproductRefGroup = {products_group} /* Products */;\n"
        '\t\t\tprojectDirPath = "";\n'
        '\t\t\tprojectRoot = "";\n'
        "\t\t\ttargets = (\n"
        f"\t\t\t\t{app_target} /* {APP_NAME} */,\n"
        "\t\t\t);\n\t\t}",
    )

    return project.render(project_uuid)


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1620" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target}"
               BuildableName = "{app}.app"
               BlueprintName = "{app}"
               ReferencedContainer = "container:{app}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{app}.app"
            BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference
         identifier = "../../../{app}.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{app}.app"
            BlueprintName = "{app}"
            ReferencedContainer = "container:{app}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

WORKSPACE = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == content:
        return
    path.write_text(content)


if __name__ == "__main__":
    write(PROJECT / "project.pbxproj", build())
    write(PROJECT / "project.xcworkspace" / "contents.xcworkspacedata", WORKSPACE)
    write(
        PROJECT / "xcshareddata" / "xcschemes" / f"{APP_NAME}.xcscheme",
        SCHEME.replace("{target}", uuid_for("target:app")).replace("{app}", APP_NAME),
    )
    team = development_team()
    print(f"wrote {PROJECT.relative_to(ROOT)}" + (f" (team {team})" if team else " (no team set)"))
