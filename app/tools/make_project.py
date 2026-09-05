#!/usr/bin/env python3
"""Generates Hush.xcodeproj from the source tree.

Hand-maintaining a .pbxproj is miserable and hand-editing one in a diff is
worse, so the project file is generated. Add a Swift file anywhere under
Hush/, HushWidgets/ or Shared/ and re-run this; membership follows the folder.

    python3 tools/make_project.py

UUIDs are derived from a hash of the object's role, so regenerating produces a
byte-identical file and the project does not churn in git.
"""
import hashlib
import os
import re
import shutil
import sys
from pathlib import Path

# A free Apple ID cannot provision App Groups, and the widget extension needs
# one to see the app's state. `--solo` emits an app-only project with no
# extension and no entitlements at all, which a free account can sign and
# install. Everything except the widgets, the Control Centre toggle and the
# Live Activity works exactly the same: UserDefaults and the file store both
# already fall back to app-local storage when the shared container is absent.
SOLO = "--solo" in sys.argv

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "Hush.xcodeproj"

APP_NAME = "Hush"
EXT_NAME = "HushWidgets"
BUNDLE_ID = "dev.brettboggs.hush"
EXT_BUNDLE_ID = f"{BUNDLE_ID}.widgets"
DEPLOYMENT_TARGET = "18.0"
SWIFT_VERSION = "5.0"
MARKETING_VERSION = "1.0"
PROJECT_VERSION = "1"

def development_team() -> str:
    """The Apple team id to sign with, preserved across regeneration.

    Xcode writes DEVELOPMENT_TEAM into project.pbxproj when you pick a team in
    Signing & Capabilities. Regenerating the project used to wipe it, so every
    push from a machine without Xcode silently un-signed the project and the
    next device build failed with "Signing requires a development team". That
    is a generator bug, not a user error.

    Checked in order: an explicit environment override, a gitignored
    Local.xcconfig, then whatever the current project file already says.
    """
    override = os.environ.get("HUSH_TEAM_ID", "").strip()
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
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcassets": "folder.assetcatalog",
    ".md": "net.daringfireball.markdown",
    ".png": "image.png",
    ".m4a": "file",
    ".xcconfig": "text.xcconfig",
}


def uuid_for(key: str) -> str:
    """24 uppercase hex characters, stable for a given key."""
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()


def quote(value: str) -> str:
    if value and all(c.isalnum() or c in "_." for c in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def swift_sources(directory: Path) -> list[Path]:
    found = [
        path.relative_to(ROOT)
        for path in sorted((ROOT / directory).rglob("*.swift"))
    ]
    return found


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

    app_swift = swift_sources(Path("Hush"))
    ext_swift = [] if SOLO else swift_sources(Path(EXT_NAME))
    shared_swift = swift_sources(Path("Shared"))

    # The asset catalog plus every bundled recording.
    resources = [Path("Hush/Assets.xcassets")] + [
        path.relative_to(ROOT)
        for path in sorted((ROOT / "Hush/Resources").rglob("*"))
        if path.is_file()
    ]
    support = [Path("Hush/Info.plist"), Path("Signing.xcconfig")]
    if not SOLO:
        support += [
            Path("Hush/Hush.entitlements"),
            Path(f"{EXT_NAME}/Info.plist"),
            Path(f"{EXT_NAME}/{EXT_NAME}.entitlements"),
        ]

    all_files = app_swift + ext_swift + shared_swift + resources + support

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
    ext_product = uuid_for("product:ext")
    project.add(
        app_product,
        f"{APP_NAME}.app",
        '{isa = PBXFileReference; explicitFileType = wrapper.application; '
        'includeInIndex = 0; path = %s; sourceTree = BUILT_PRODUCTS_DIR; }'
        % quote(f"{APP_NAME}.app"),
    )
    project.add(
        ext_product,
        f"{EXT_NAME}.appex",
        '{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; '
        'includeInIndex = 0; path = %s; sourceTree = BUILT_PRODUCTS_DIR; }'
        % quote(f"{EXT_NAME}.appex"),
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

    app_sources = build_files(app_swift + shared_swift, "Sources-app")
    ext_sources = build_files(ext_swift + shared_swift, "Sources-ext")
    app_resources = build_files(resources, "Resources-app")

    embed_file = uuid_for("buildfile:embed-appex")
    project.add(
        embed_file,
        f"{EXT_NAME}.appex in Embed Foundation Extensions",
        "{isa = PBXBuildFile; fileRef = %s /* %s.appex */; "
        "settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; }" % (ext_product, EXT_NAME),
    )

    # ---- Groups -----------------------------------------------------------
    def file_list(entries) -> str:
        if not entries:
            return "(\n\t\t\t)"
        rows = "".join(
            f"\n\t\t\t\t{uuid} /* {name} */," for uuid, name in entries
        )
        return "(%s\n\t\t\t)" % rows

    def make_group(uuid: str, name: str, path: str | None, children: list[tuple[str, str]]) -> None:
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
        direct = sorted(
            [f for f in files if f.parent == directory],
            key=lambda p: p.name,
        )
        # The first path component below `directory` for every nested file.
        # Taking `f.parent` here would skip intermediate directories that hold
        # only other directories, orphaning everything beneath them.
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

    app_files = app_swift + resources + [Path("Hush/Info.plist")]
    if not SOLO:
        app_files.append(Path("Hush/Hush.entitlements"))
    app_group, _ = group_tree(Path("Hush"), app_files)
    ext_files = [] if SOLO else ext_swift + [
        Path(f"{EXT_NAME}/Info.plist"), Path(f"{EXT_NAME}/{EXT_NAME}.entitlements")
    ]
    ext_group, _ = group_tree(Path(EXT_NAME), ext_files)
    shared_group, _ = group_tree(Path("Shared"), shared_swift)

    products_group = uuid_for("group:products")
    products = [(app_product, f"{APP_NAME}.app")]
    if not SOLO:
        products.append((ext_product, f"{EXT_NAME}.appex"))
    make_group(products_group, "Products", None, products)

    main_group = uuid_for("group:main")
    signing_ref = file_refs["Signing.xcconfig"]
    top = [(app_group, "Hush")]
    if not SOLO:
        top.append((ext_group, EXT_NAME))
    top += [
        (shared_group, "Shared"),
        (signing_ref, "Signing.xcconfig"),
        (products_group, "Products"),
    ]
    make_group(main_group, "", None, top)

    # ---- Build phases -----------------------------------------------------
    def phase(uuid: str, isa: str, name: str, entries, extra: str = "") -> None:
        project.add(
            uuid,
            name,
            "{\n\t\t\tisa = %s;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tfiles = %s;\n"
            "%s"
            "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}"
            % (isa, file_list(entries), extra),
        )

    app_sources_phase = uuid_for("phase:app:sources")
    app_frameworks_phase = uuid_for("phase:app:frameworks")
    app_resources_phase = uuid_for("phase:app:resources")
    app_embed_phase = uuid_for("phase:app:embed")
    ext_sources_phase = uuid_for("phase:ext:sources")
    ext_frameworks_phase = uuid_for("phase:ext:frameworks")
    ext_resources_phase = uuid_for("phase:ext:resources")

    phase(app_sources_phase, "PBXSourcesBuildPhase", "Sources", app_sources)
    phase(app_frameworks_phase, "PBXFrameworksBuildPhase", "Frameworks", [])
    phase(app_resources_phase, "PBXResourcesBuildPhase", "Resources", app_resources)
    phase(ext_sources_phase, "PBXSourcesBuildPhase", "Sources", ext_sources)
    phase(ext_frameworks_phase, "PBXFrameworksBuildPhase", "Frameworks", [])
    phase(ext_resources_phase, "PBXResourcesBuildPhase", "Resources", [])

    project.add(
        app_embed_phase,
        "Embed Foundation Extensions",
        "{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        '\t\t\tdstPath = "";\n'
        "\t\t\tdstSubfolderSpec = 13;\n"
        "\t\t\tfiles = %s;\n"
        '\t\t\tname = "Embed Foundation Extensions";\n'
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}"
        % file_list([(embed_file, f"{EXT_NAME}.appex")]),
    )

    # ---- Dependency -------------------------------------------------------
    project_uuid = uuid_for("project")
    proxy = uuid_for("proxy:ext")
    dependency = uuid_for("dependency:ext")
    ext_target = uuid_for("target:ext")
    app_target = uuid_for("target:app")

    project.add(
        proxy,
        "PBXContainerItemProxy",
        "{\n\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = {project_uuid} /* Project object */;\n"
        "\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {ext_target};\n"
        f"\t\t\tremoteInfo = {EXT_NAME};\n\t\t}}",
    )
    project.add(
        dependency,
        "PBXTargetDependency",
        "{\n\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {ext_target} /* {EXT_NAME} */;\n"
        f"\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;\n\t\t}}",
    )

    # ---- Build configurations --------------------------------------------
    def settings_block(pairs: dict[str, str]) -> str:
        rows = "".join(
            f"\n\t\t\t\t{key} = {value};" for key, value in sorted(pairs.items())
        )
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
        "INFOPLIST_FILE": "Hush/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t)',
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    if not SOLO:
        app_common["CODE_SIGN_ENTITLEMENTS"] = "Hush/Hush.entitlements"
    if team:
        app_common["DEVELOPMENT_TEAM"] = team

    ext_common = {
        "CODE_SIGN_ENTITLEMENTS": f"{EXT_NAME}/{EXT_NAME}.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": PROJECT_VERSION,
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": f"{EXT_NAME}/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '(\n\t\t\t\t\t"$(inherited)",\n\t\t\t\t\t"@executable_path/Frameworks",\n\t\t\t\t\t"@executable_path/../../Frameworks",\n\t\t\t\t)',
        "MARKETING_VERSION": MARKETING_VERSION,
        "PRODUCT_BUNDLE_IDENTIFIER": EXT_BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SKIP_INSTALL": "YES",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    if team:
        ext_common["DEVELOPMENT_TEAM"] = team

    configs = {
        "project:Debug": debug,
        "project:Release": release,
        "app:Debug": app_common,
        "app:Release": app_common,
        "ext:Debug": ext_common,
        "ext:Release": ext_common,
    }
    config_uuids = {}
    for key, values in configs.items():
        name = key.split(":")[1]
        uuid = uuid_for(f"buildconfig:{key}")
        config_uuids[key] = uuid
        base = ""
        if key.startswith(("app:", "ext:")):
            base = (f"\t\t\tbaseConfigurationReference = {signing_ref} "
                    "/* Signing.xcconfig */;\n")
        project.add(
            uuid,
            name,
            "{\n\t\t\tisa = XCBuildConfiguration;\n"
            f"{base}"
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
    ext_config_list = config_list("ext")

    # ---- Targets ----------------------------------------------------------
    app_target_lines = [
        "{\n\t\t\tisa = PBXNativeTarget;\n",
        f"\t\t\tbuildConfigurationList = {app_config_list};\n",
        "\t\t\tbuildPhases = (\n",
        f"\t\t\t\t{app_sources_phase} /* Sources */,\n",
        f"\t\t\t\t{app_frameworks_phase} /* Frameworks */,\n",
        f"\t\t\t\t{app_resources_phase} /* Resources */,\n",
    ]
    if not SOLO:
        app_target_lines.append(
            f"\t\t\t\t{app_embed_phase} /* Embed Foundation Extensions */,\n"
        )
    app_target_lines += [
        "\t\t\t);\n",
        "\t\t\tbuildRules = (\n\t\t\t);\n",
        "\t\t\tdependencies = (\n",
    ]
    if not SOLO:
        app_target_lines.append(f"\t\t\t\t{dependency} /* PBXTargetDependency */,\n")
    app_target_lines += [
        "\t\t\t);\n",
        f"\t\t\tname = {APP_NAME};\n",
        f"\t\t\tproductName = {APP_NAME};\n",
        f"\t\t\tproductReference = {app_product} /* {APP_NAME}.app */;\n",
        '\t\t\tproductType = "com.apple.product-type.application";\n\t\t}',
    ]
    project.add(app_target, APP_NAME, "".join(app_target_lines))
    if not SOLO:
      project.add(
        ext_target,
        EXT_NAME,
        "{\n\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {ext_config_list};\n"
        "\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{ext_sources_phase} /* Sources */,\n"
        f"\t\t\t\t{ext_frameworks_phase} /* Frameworks */,\n"
        f"\t\t\t\t{ext_resources_phase} /* Resources */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n\t\t\t);\n"
        "\t\t\tdependencies = (\n\t\t\t);\n"
        f"\t\t\tname = {EXT_NAME};\n"
        f"\t\t\tproductName = {EXT_NAME};\n"
        f"\t\t\tproductReference = {ext_product} /* {EXT_NAME}.appex */;\n"
        '\t\t\tproductType = "com.apple.product-type.app-extension";\n\t\t}',
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
        f"{'' if SOLO else chr(9) * 5 + ext_target + ' = {' + chr(10) + chr(9) * 6 + 'CreatedOnToolsVersion = 16.2;' + chr(10) + chr(9) * 5 + '};' + chr(10)}"
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
        f"{'' if SOLO else chr(9) * 4 + ext_target + ' /* ' + EXT_NAME + ' */,' + chr(10)}"
        "\t\t\t);\n\t\t}",
    )

    if SOLO:
        for key in list(project.objects):
            if key in {ext_target, ext_product, ext_config_list, proxy, dependency,
                       ext_sources_phase, ext_frameworks_phase, ext_resources_phase,
                       app_embed_phase, embed_file, ext_group,
                       config_uuids["ext:Debug"], config_uuids["ext:Release"]}:
                del project.objects[key]
        for path in ext_swift:
            project.objects.pop(uuid_for(f"buildfile:Sources-ext:{path}"), None)
        for path in shared_swift:
            project.objects.pop(uuid_for(f"buildfile:Sources-ext:{path}"), None)
        for path in [Path(f"{EXT_NAME}/Info.plist"),
                     Path(f"{EXT_NAME}/{EXT_NAME}.entitlements")]:
            project.objects.pop(uuid_for(f"fileref:{path}"), None)
        for path in swift_sources(Path(EXT_NAME)):
            project.objects.pop(uuid_for(f"fileref:{path}"), None)

    return project.render(project_uuid)


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1620" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_target}"
               BuildableName = "Hush.app"
               BlueprintName = "Hush"
               ReferencedContainer = "container:Hush.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "Hush.app"
            BlueprintName = "Hush"
            ReferencedContainer = "container:Hush.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference
         identifier = "../../../Hush.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target}"
            BuildableName = "Hush.app"
            BlueprintName = "Hush"
            ReferencedContainer = "container:Hush.xcodeproj">
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


if __name__ == "__main__":
    preserved = development_team()
    if preserved:
        os.environ["HUSH_TEAM_ID"] = preserved

    if PROJECT.exists():
        shutil.rmtree(PROJECT)
    (PROJECT / "project.xcworkspace").mkdir(parents=True)
    (PROJECT / "xcshareddata/xcschemes").mkdir(parents=True)

    (PROJECT / "project.pbxproj").write_text(build())
    if SOLO:
        print("  solo mode: app target only, no App Group, no widget extension")
    (PROJECT / "project.xcworkspace/contents.xcworkspacedata").write_text(WORKSPACE)
    (PROJECT / "xcshareddata/xcschemes/Hush.xcscheme").write_text(
        SCHEME.replace("{app_target}", uuid_for("target:app"))
    )
    lines = (PROJECT / "project.pbxproj").read_text().count("\n")
    signing = f"team {preserved}" if preserved else "no team set yet"
    print(f"wrote {PROJECT.relative_to(ROOT)} ({lines} lines, {signing})")
