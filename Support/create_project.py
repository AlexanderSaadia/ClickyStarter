"""Regenerate the small Xcode project without third-party dependencies."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parents[1]
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(name, body):
    key = ident(name)
    objects[key] = body
    return key

def refs(values):
    return '(' + ', '.join(values) + (',' if values else '') + ')'

def settings(values):
    result = []
    for key, value in values.items():
        result.append(f'{key} = "{value}";')
    return '{ ' + ' '.join(result) + ' }'

app_sources = sorted((root / 'ClickyStarter').rglob('*.swift'))
test_sources = sorted((root / 'ClickyStarterTests').rglob('*.swift'))

def folder_group(directory, display_name=None, group_key=None, compile_sources=False):
    """Mirror real folders in Xcode; individual files display only their names."""
    children, build_ids = [], []
    folder_order = {'Application': 0, 'Models': 1, 'ViewModels': 2, 'Views': 3, 'Services': 4}
    paths = sorted(directory.iterdir(), key=lambda path: (
        not path.is_dir(), folder_order.get(path.name, 100), path.name.lower()))
    for path in paths:
        if path.name.startswith('.') or path.name == '__pycache__':
            continue
        relative = path.relative_to(root).as_posix()
        if path.is_dir():
            child, child_builds = folder_group(path, compile_sources=compile_sources)
            children.append(child)
            build_ids.extend(child_builds)
            continue
        types = {'.swift': 'sourcecode.swift', '.py': 'text.script.python', '.md': 'net.daringfireball.markdown'}
        if path.suffix not in types:
            continue
        file_id = add('file:' + relative, f'isa = PBXFileReference; lastKnownFileType = {types[path.suffix]}; path = "{path.name}"; sourceTree = "<group>";')
        children.append(file_id)
        if compile_sources and path.suffix == '.swift':
            build_ids.append(add('build:' + relative, f'isa = PBXBuildFile; fileRef = {file_id};'))
    name = display_name or directory.name
    group = add(group_key or ('folder:' + directory.relative_to(root).as_posix()),
                f'isa = PBXGroup; children = {refs(children)}; name = "{name}"; path = "{directory.name}"; sourceTree = "<group>";')
    return group, build_ids

def source_group(name, directory):
    group, build_ids = folder_group(directory, display_name=name, group_key=name + 'group', compile_sources=True)
    phase = add(name + 'sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(build_ids)}; runOnlyForDeploymentPostprocessing = 0;')
    return group, phase

app_group, app_phase = source_group('App', root / 'ClickyStarter')
test_group, test_phase = source_group('Tests', root / 'ClickyStarterTests')
support_group, _ = folder_group(root / 'Support')
app_product = add('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = ClickyStarter.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ClickyStarterTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; children = {refs([app_product, test_product])}; name = Products; sourceTree = "<group>";')
readme = add('readme', 'isa = PBXFileReference; lastKnownFileType = net.daringfireball.markdown; path = README.md; sourceTree = "<group>";')
file_guide = add('file-guide', 'isa = PBXFileReference; lastKnownFileType = net.daringfireball.markdown; path = "FILE GUIDE.md"; sourceTree = "<group>";')
main_group = add('main-group', f'isa = PBXGroup; children = {refs([app_group, test_group, support_group, readme, file_guide, products])}; sourceTree = "<group>";')

def configs(name, values):
    config_ids = []
    for mode in ['Debug', 'Release']:
        current = dict(values)
        current['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if mode == 'Debug' else '-O'
        if mode == 'Debug':
            current['ENABLE_TESTABILITY'] = 'YES'
            current['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        config_ids.append(add(name + mode, f'isa = XCBuildConfiguration; buildSettings = {settings(current)}; name = {mode};'))
    return add(name + '-configs', f'isa = XCConfigurationList; buildConfigurations = {refs(config_ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_configs = configs('project', {'MACOSX_DEPLOYMENT_TARGET': '14.0', 'SDKROOT': 'macosx', 'SWIFT_VERSION': '6.0', 'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'complete', 'CODE_SIGN_IDENTITY': '-', 'CODE_SIGN_STYLE': 'Manual'})
app_configs = configs('app', {'PRODUCT_BUNDLE_IDENTIFIER': 'com.alexandersaadia.ClickyStarter', 'PRODUCT_NAME': '$(TARGET_NAME)', 'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_KEY_CFBundleDisplayName': 'Clicky Starter', 'INFOPLIST_KEY_LSApplicationCategoryType': 'public.app-category.productivity', 'ENABLE_APP_SANDBOX': 'NO', 'ENABLE_HARDENED_RUNTIME': 'NO', 'COMBINE_HIDPI_IMAGES': 'YES', 'MARKETING_VERSION': '0.1.0', 'CURRENT_PROJECT_VERSION': '1', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/../Frameworks'})
test_configs = configs('test', {'PRODUCT_BUNDLE_IDENTIFIER': 'com.alexandersaadia.ClickyStarterTests', 'PRODUCT_NAME': '$(TARGET_NAME)', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/ClickyStarter.app/Contents/MacOS/ClickyStarter', 'BUNDLE_LOADER': '$(TEST_HOST)', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'})
app_target = add('app-target', f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {refs([app_phase])}; buildRules = (); dependencies = (); name = ClickyStarter; productName = ClickyStarter; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy = add('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = ClickyStarter;')
dependency = add('dependency', f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
test_target = add('test-target', f'isa = PBXNativeTarget; buildConfigurationList = {test_configs}; buildPhases = {refs([test_phase])}; buildRules = (); dependencies = {refs([dependency])}; name = ClickyStarterTests; productName = ClickyStarterTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
project = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([app_target, test_target])};')
project_dir = root / 'ClickyStarter.xcodeproj'
project_dir.mkdir(exist_ok=True)
contents = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
for key, body in objects.items(): contents += f'{key} = {{ {body} }};\n'
contents += f'}}; rootObject = {project}; }}\n'
(project_dir / 'project.pbxproj').write_text(contents)
schemes = project_dir / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
def reference(target, product, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:ClickyStarter.xcodeproj"/>'
app_ref = reference(app_target, 'ClickyStarter.app', 'ClickyStarter')
test_ref = reference(test_target, 'ClickyStarterTests.xctest', 'ClickyStarterTests')
(schemes / 'ClickyStarter.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print('Generated ClickyStarter.xcodeproj')
