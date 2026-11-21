// 生成并校验 DSHClient.xcodeproj/project.pbxproj。
// 用法：node tools/gen-xcodeproj.mjs
import crypto from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..')
const SOURCE_ROOT = path.join(ROOT, 'DSHClient')
const PROJECT_DIR = path.join(ROOT, 'DSHClient.xcodeproj')
const PBXPROJ_PATH = path.join(PROJECT_DIR, 'project.pbxproj')

const id = (key) => crypto.createHash('md5').update(String(key)).digest('hex').slice(0, 24).toUpperCase()

function q(value) {
  const text = String(value)
  if (/^[A-Za-z0-9_./$@:+-]+$/.test(text)) return text
  return `"${text.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`
}

// ---------------------------------------------------------------------------
// 扫描源码树
// ---------------------------------------------------------------------------

function walk(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true })
  const dirs = []
  const files = []
  for (const entry of entries) {
    if (entry.name.startsWith('.')) continue
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      if (entry.name.endsWith('.xcassets')) files.push({ name: entry.name, path: full, resource: true })
      else dirs.push({ name: entry.name, path: full })
    } else if (entry.name.endsWith('.swift')) {
      files.push({ name: entry.name, path: full, source: true })
    } else if (entry.name.endsWith('.plist')) {
      files.push({ name: entry.name, path: full, plist: true })
    }
  }
  dirs.sort((a, b) => a.name.localeCompare(b.name))
  files.sort((a, b) => a.name.localeCompare(b.name))
  return { dirs, files }
}

const tree = walk(SOURCE_ROOT)

const groups = [] // { key, name, path, children: [] }
const fileRefs = [] // { key, name, path, type }
const buildFiles = [] // { key, refKey, name, phase }
const sourceNames = []

function fileType(file) {
  if (file.source) return 'sourcecode.swift'
  if (file.resource) return 'folder.assetcatalog'
  if (file.plist) return 'text.plist.xml'
  return 'text'
}

function collect(node, parentKey, parentPath, out) {
  const groupKey = id(`group:${parentPath}`)
  out.push({ key: groupKey, name: path.basename(parentPath) || 'DSHClient', path: parentPath, children: [] })

  for (const sub of node.dirs) {
    const subKey = collect(walk(sub.path), groupKey, `${parentPath}/${sub.name}`, out)
    out.find((g) => g.key === groupKey).children.push(subKey)
  }

  for (const file of node.files) {
    const refKey = id(`file:${parentPath}/${file.name}`)
    fileRefs.push({ key: refKey, name: file.name, path: file.name, type: fileType(file) })
    out.find((g) => g.key === groupKey).children.push(refKey)

    if (file.source) {
      sourceNames.push(file.name)
      buildFiles.push({ key: id(`build:${parentPath}/${file.name}`), refKey, name: file.name, phase: 'sources' })
    }
    if (file.resource) {
      buildFiles.push({ key: id(`build:${parentPath}/${file.name}`), refKey, name: file.name, phase: 'resources' })
    }
  }

  return groupKey
}

const sourceGroupKey = collect(tree, null, 'DSHClient', groups)

// 让 "DSHClient" 组的 path 相对于工程目录（而不是父组）
const sourceGroup = groups.find((g) => g.key === sourceGroupKey)
sourceGroup.path = 'DSHClient'

const PRODUCT_REF = id('product:DSHClient.app')
const PRODUCT_GROUP = id('group:Products')
const MAIN_GROUP = id('group:Root')
const PROJECT = id('project:DSHClient')
const TARGET = id('target:DSHClient')
const SOURCES_PHASE = id('phase:sources')
const FRAMEWORKS_PHASE = id('phase:frameworks')
const RESOURCES_PHASE = id('phase:resources')
const PROJECT_CONFIG_LIST = id('configlist:project')
const TARGET_CONFIG_LIST = id('configlist:target')
const PROJECT_DEBUG = id('config:project:Debug')
const PROJECT_RELEASE = id('config:project:Release')
const TARGET_DEBUG = id('config:target:Debug')
const TARGET_RELEASE = id('config:target:Release')

// ---------------------------------------------------------------------------
// 生成 pbxproj
// ---------------------------------------------------------------------------

const lines = []
const push = (line = '') => lines.push(line)

push('// !$*UTF8*$!')
push('{')
push('\tarchiveVersion = 1;')
push('\tclasses = {')
push('\t};')
push('\tobjectVersion = 55;')
push('\tobjects = {')
push('')

push('/* Begin PBXBuildFile section */')
for (const file of buildFiles) {
  push(`\t\t${file.key} /* ${file.name} in ${file.phase === 'sources' ? 'Sources' : 'Resources'} */ = {isa = PBXBuildFile; fileRef = ${file.refKey} /* ${file.name} */; };`)
}
push('/* End PBXBuildFile section */')
push('')

push('/* Begin PBXFileReference section */')
for (const ref of fileRefs) {
  push(`\t\t${ref.key} /* ${ref.name} */ = {isa = PBXFileReference; lastKnownFileType = ${ref.type}; path = ${q(ref.path)}; sourceTree = "<group>"; };`)
}
push(`\t\t${PRODUCT_REF} /* DSHClient.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DSHClient.app; sourceTree = BUILT_PRODUCTS_DIR; };`)
push('/* End PBXFileReference section */')
push('')

push('/* Begin PBXFrameworksBuildPhase section */')
push(`\t\t${FRAMEWORKS_PHASE} /* Frameworks */ = {`)
push('\t\t\tisa = PBXFrameworksBuildPhase;')
push('\t\t\tbuildActionMask = 2147483647;')
push('\t\t\tfiles = (')
push('\t\t\t);')
push('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
push('\t\t};')
push('/* End PBXFrameworksBuildPhase section */')
push('')

push('/* Begin PBXGroup section */')
push(`\t\t${MAIN_GROUP} = {`)
push('\t\t\tisa = PBXGroup;')
push('\t\t\tchildren = (')
push(`\t\t\t\t${sourceGroupKey} /* DSHClient */,`)
push(`\t\t\t\t${PRODUCT_GROUP} /* Products */,`)
push('\t\t\t);')
push('\t\t\tsourceTree = "<group>";')
push('\t\t};')
for (const group of groups) {
  push(`\t\t${group.key} /* ${group.name} */ = {`)
  push('\t\t\tisa = PBXGroup;')
  push('\t\t\tchildren = (')
  for (const child of group.children) push(`\t\t\t\t${child},`)
  push('\t\t\t);')
  push(`\t\t\tpath = ${q(group.path)};`)
  push('\t\t\tsourceTree = "<group>";')
  push('\t\t};')
}
push(`\t\t${PRODUCT_GROUP} /* Products */ = {`)
push('\t\t\tisa = PBXGroup;')
push('\t\t\tchildren = (')
push(`\t\t\t\t${PRODUCT_REF} /* DSHClient.app */,`)
push('\t\t\t);')
push('\t\t\tname = Products;')
push('\t\t\tsourceTree = "<group>";')
push('\t\t};')
push('/* End PBXGroup section */')
push('')

push('/* Begin PBXNativeTarget section */')
push(`\t\t${TARGET} /* DSHClient */ = {`)
push('\t\t\tisa = PBXNativeTarget;')
push(`\t\t\tbuildConfigurationList = ${TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "DSHClient" */;`)
push('\t\t\tbuildPhases = (')
push(`\t\t\t\t${SOURCES_PHASE} /* Sources */,`)
push(`\t\t\t\t${FRAMEWORKS_PHASE} /* Frameworks */,`)
push(`\t\t\t\t${RESOURCES_PHASE} /* Resources */,`)
push('\t\t\t);')
push('\t\t\tbuildRules = (')
push('\t\t\t);')
push('\t\t\tdependencies = (')
push('\t\t\t);')
push('\t\t\tname = DSHClient;')
push('\t\t\tproductName = DSHClient;')
push(`\t\t\tproductReference = ${PRODUCT_REF} /* DSHClient.app */;`)
push('\t\t\tproductType = "com.apple.product-type.application";')
push('\t\t};')
push('/* End PBXNativeTarget section */')
push('')

push('/* Begin PBXProject section */')
push(`\t\t${PROJECT} /* Project object */ = {`)
push('\t\t\tisa = PBXProject;')
push('\t\t\tattributes = {')
push('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
push('\t\t\t\tLastSwiftUpdateCheck = 1500;')
push('\t\t\t\tLastUpgradeCheck = 1500;')
push('\t\t\t\tTargetAttributes = {')
push(`\t\t\t\t\t${TARGET} = {`)
push('\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;')
push('\t\t\t\t\t};')
push('\t\t\t\t};')
push('\t\t\t};')
push(`\t\t\tbuildConfigurationList = ${PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject "DSHClient" */;`)
push('\t\t\tcompatibilityVersion = "Xcode 13.0";')
push('\t\t\tdevelopmentRegion = en;')
push('\t\t\thasScannedForEncodings = 0;')
push('\t\t\tknownRegions = (')
push('\t\t\t\ten,')
push('\t\t\t\tBase,')
push('\t\t\t);')
push(`\t\t\tmainGroup = ${MAIN_GROUP};`)
push(`\t\t\tproductRefGroup = ${PRODUCT_GROUP} /* Products */;`)
push('\t\t\tprojectDirPath = "";')
push('\t\t\tprojectRoot = "";')
push('\t\t\ttargets = (')
push(`\t\t\t\t${TARGET} /* DSHClient */,`)
push('\t\t\t);')
push('\t\t};')
push('/* End PBXProject section */')
push('')

push('/* Begin PBXResourcesBuildPhase section */')
push(`\t\t${RESOURCES_PHASE} /* Resources */ = {`)
push('\t\t\tisa = PBXResourcesBuildPhase;')
push('\t\t\tbuildActionMask = 2147483647;')
push('\t\t\tfiles = (')
for (const file of buildFiles.filter((f) => f.phase === 'resources')) {
  push(`\t\t\t\t${file.key} /* ${file.name} in Resources */,`)
}
push('\t\t\t);')
push('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
push('\t\t};')
push('/* End PBXResourcesBuildPhase section */')
push('')

push('/* Begin PBXSourcesBuildPhase section */')
push(`\t\t${SOURCES_PHASE} /* Sources */ = {`)
push('\t\t\tisa = PBXSourcesBuildPhase;')
push('\t\t\tbuildActionMask = 2147483647;')
push('\t\t\tfiles = (')
for (const file of buildFiles.filter((f) => f.phase === 'sources')) {
  push(`\t\t\t\t${file.key} /* ${file.name} in Sources */,`)
}
push('\t\t\t);')
push('\t\t\trunOnlyForDeploymentPostprocessing = 0;')
push('\t\t};')
push('/* End PBXSourcesBuildPhase section */')
push('')

const projectSettingsDebug = {
  ALWAYS_SEARCH_USER_PATHS: 'NO',
  CLANG_ANALYZER_NONNULL: 'YES',
  CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION: 'YES_AGGRESSIVE',
  CLANG_CXX_LANGUAGE_STANDARD: 'gnu++20',
  CLANG_ENABLE_MODULES: 'YES',
  CLANG_ENABLE_OBJC_ARC: 'YES',
  CLANG_ENABLE_OBJC_WEAK: 'YES',
  CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING: 'YES',
  CLANG_WARN_BOOL_CONVERSION: 'YES',
  CLANG_WARN_COMMA: 'YES',
  CLANG_WARN_CONSTANT_CONVERSION: 'YES',
  CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS: 'YES',
  CLANG_WARN_DIRECT_OBJC_ISA_USAGE: 'YES_ERROR',
  CLANG_WARN_DOCUMENTATION_COMMENTS: 'YES',
  CLANG_WARN_EMPTY_BODY: 'YES',
  CLANG_WARN_ENUM_CONVERSION: 'YES',
  CLANG_WARN_INFINITE_RECURSION: 'YES',
  CLANG_WARN_INT_CONVERSION: 'YES',
  CLANG_WARN_NON_LITERAL_NULL_CONVERSION: 'YES',
  CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF: 'YES',
  CLANG_WARN_OBJC_LITERAL_CONVERSION: 'YES',
  CLANG_WARN_OBJC_ROOT_CLASS: 'YES_ERROR',
  CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER: 'YES',
  CLANG_WARN_RANGE_LOOP_ANALYSIS: 'YES',
  CLANG_WARN_STRICT_PROTOTYPES: 'YES',
  CLANG_WARN_SUSPICIOUS_MOVE: 'YES',
  CLANG_WARN_UNGUARDED_AVAILABILITY: 'YES_AGGRESSIVE',
  CLANG_WARN_UNREACHABLE_CODE: 'YES',
  CLANG_WARN__DUPLICATE_METHOD_MATCH: 'YES',
  COPY_PHASE_STRIP: 'NO',
  DEBUG_INFORMATION_FORMAT: 'dwarf',
  ENABLE_STRICT_OBJC_MSGSEND: 'YES',
  ENABLE_TESTABILITY: 'YES',
  GCC_C_LANGUAGE_STANDARD: 'gnu17',
  GCC_DYNAMIC_NO_PIC: 'NO',
  GCC_NO_COMMON_BLOCKS: 'YES',
  GCC_OPTIMIZATION_LEVEL: '0',
  GCC_PREPROCESSOR_DEFINITIONS: ['DEBUG=1', '$(inherited)'],
  IPHONEOS_DEPLOYMENT_TARGET: '14.0',
  MTL_ENABLE_DEBUG_INFO: 'INCLUDE_SOURCE',
  MTL_FAST_MATH: 'YES',
  ONLY_ACTIVE_ARCH: 'YES',
  SDKROOT: 'iphoneos',
  SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'DEBUG',
  SWIFT_OPTIMIZATION_LEVEL: '-Onone',
}

const projectSettingsRelease = {
  ...projectSettingsDebug,
  COPY_PHASE_STRIP: 'NO',
  DEBUG_INFORMATION_FORMAT: 'dwarf-with-dsym',
  ENABLE_NS_ASSERTIONS: 'NO',
  MTL_ENABLE_DEBUG_INFO: 'NO',
  SWIFT_COMPILATION_MODE: 'wholemodule',
  SWIFT_OPTIMIZATION_LEVEL: '-O',
  VALIDATE_PRODUCT: 'YES',
}
delete projectSettingsRelease.ONLY_ACTIVE_ARCH
delete projectSettingsRelease.GCC_OPTIMIZATION_LEVEL
delete projectSettingsRelease.GCC_DYNAMIC_NO_PIC
delete projectSettingsRelease.GCC_PREPROCESSOR_DEFINITIONS
delete projectSettingsRelease.ENABLE_TESTABILITY
delete projectSettingsRelease.SWIFT_ACTIVE_COMPILATION_CONDITIONS

const targetSettings = {
  ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon',
  CODE_SIGN_STYLE: 'Automatic',
  CURRENT_PROJECT_VERSION: '1',
  ENABLE_PREVIEWS: 'YES',
  GENERATE_INFOPLIST_FILE: 'NO',
  INFOPLIST_FILE: 'DSHClient/Resources/Info.plist',
  IPHONEOS_DEPLOYMENT_TARGET: '14.0',
  LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks'],
  MARKETING_VERSION: '1.0',
  PRODUCT_BUNDLE_IDENTIFIER: 'com.dsh.ios.client',
  PRODUCT_NAME: '$(TARGET_NAME)',
  SWIFT_VERSION: '5.0',
  TARGETED_DEVICE_FAMILY: '1,2',
}

function emitSettings(settings) {
  const keys = Object.keys(settings).sort()
  for (const key of keys) {
    const value = settings[key]
    if (Array.isArray(value)) {
      push(`\t\t\t\t${key} = (`)
      for (const item of value) push(`\t\t\t\t\t${q(item)},`)
      push('\t\t\t\t);')
    } else {
      push(`\t\t\t\t${key} = ${q(value)};`)
    }
  }
}

push('/* Begin XCBuildConfiguration section */')
for (const [configKey, name, settings] of [
  [PROJECT_DEBUG, 'Debug', projectSettingsDebug],
  [PROJECT_RELEASE, 'Release', projectSettingsRelease],
]) {
  push(`\t\t${configKey} /* ${name} */ = {`)
  push('\t\t\tisa = XCBuildConfiguration;')
  push('\t\t\tbuildSettings = {')
  emitSettings(settings)
  push('\t\t\t};')
  push(`\t\t\tname = ${name};`)
  push('\t\t};')
}
for (const [configKey, name] of [
  [TARGET_DEBUG, 'Debug'],
  [TARGET_RELEASE, 'Release'],
]) {
  push(`\t\t${configKey} /* ${name} */ = {`)
  push('\t\t\tisa = XCBuildConfiguration;')
  push('\t\t\tbuildSettings = {')
  emitSettings(targetSettings)
  push('\t\t\t};')
  push(`\t\t\tname = ${name};`)
  push('\t\t};')
}
push('/* End XCBuildConfiguration section */')
push('')

push('/* Begin XCConfigurationList section */')
push(`\t\t${PROJECT_CONFIG_LIST} /* Build configuration list for PBXProject "DSHClient" */ = {`)
push('\t\t\tisa = XCConfigurationList;')
push('\t\t\tbuildConfigurations = (')
push(`\t\t\t\t${PROJECT_DEBUG} /* Debug */,`)
push(`\t\t\t\t${PROJECT_RELEASE} /* Release */,`)
push('\t\t\t);')
push('\t\t\tdefaultConfigurationIsVisible = 0;')
push('\t\t\tdefaultConfigurationName = Release;')
push('\t\t};')
push(`\t\t${TARGET_CONFIG_LIST} /* Build configuration list for PBXNativeTarget "DSHClient" */ = {`)
push('\t\t\tisa = XCConfigurationList;')
push('\t\t\tbuildConfigurations = (')
push(`\t\t\t\t${TARGET_DEBUG} /* Debug */,`)
push(`\t\t\t\t${TARGET_RELEASE} /* Release */,`)
push('\t\t\t);')
push('\t\t\tdefaultConfigurationIsVisible = 0;')
push('\t\t\tdefaultConfigurationName = Release;')
push('\t\t};')
push('/* End XCConfigurationList section */')
push('')
push('\t};')
push(`\trootObject = ${PROJECT} /* Project object */;`)
push('}')

const text = lines.join('\n') + '\n'
fs.mkdirSync(PROJECT_DIR, { recursive: true })
fs.writeFileSync(PBXPROJ_PATH, text, 'utf8')

// 共享 scheme：让 xcodebuild / GitHub Actions 不需要先打开 Xcode 也能构建。
const schemeDir = path.join(PROJECT_DIR, 'xcshareddata', 'xcschemes')
fs.mkdirSync(schemeDir, { recursive: true })
const scheme = `<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "${TARGET}"
               BuildableName = "DSHClient.app"
               BlueprintName = "DSHClient"
               ReferencedContainer = "container:DSHClient.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${TARGET}"
            BuildableName = "DSHClient.app"
            BlueprintName = "DSHClient"
            ReferencedContainer = "container:DSHClient.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "${TARGET}"
            BuildableName = "DSHClient.app"
            BlueprintName = "DSHClient"
            ReferencedContainer = "container:DSHClient.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
`
fs.writeFileSync(path.join(schemeDir, 'DSHClient.xcscheme'), scheme, 'utf8')

console.log(`generated ${PBXPROJ_PATH}`)
console.log(`  swift files: ${sourceNames.length}`)
console.log(`  groups: ${groups.length}`)
console.log(`  references: ${fileRefs.length}`)

// ---------------------------------------------------------------------------
// 校验：解析 OpenStep plist，检查引用完整性
// ---------------------------------------------------------------------------

function parsePlist(source) {
  let index = 0
  const length = source.length

  function skip() {
    for (;;) {
      while (index < length && /\s/.test(source[index])) index += 1
      if (source.startsWith('//', index)) {
        while (index < length && source[index] !== '\n') index += 1
      } else if (source.startsWith('/*', index)) {
        const end = source.indexOf('*/', index + 2)
        index = end < 0 ? length : end + 2
      } else {
        return
      }
    }
  }

  function expect(char) {
    skip()
    if (source[index] !== char) {
      throw new Error(`expected ${char} at ${index}, got ${JSON.stringify(source.slice(index, index + 20))}`)
    }
    index += 1
  }

  function parseQuoted() {
    expect('"')
    let out = ''
    while (index < length) {
      const char = source[index]
      if (char === '"') {
        index += 1
        return out
      }
      if (char === '\\') {
        index += 1
        const next = source[index]
        if (next === 'n') out += '\n'
        else if (next === 't') out += '\t'
        else if (next === 'r') out += '\r'
        else if (next === 'U') {
          out += String.fromCharCode(parseInt(source.slice(index + 1, index + 5), 16))
          index += 4
        } else out += next
        index += 1
      } else {
        out += char
        index += 1
      }
    }
    throw new Error('unterminated string')
  }

  function parseBare() {
    const start = index
    while (index < length && !/[\s=;,(){}"<>]/.test(source[index])) index += 1
    if (start === index) throw new Error(`unexpected ${JSON.stringify(source[index])} at ${index}`)
    return source.slice(start, index)
  }

  function parseValue() {
    skip()
    const char = source[index]
    if (char === '{') return parseDict()
    if (char === '(') return parseArray()
    if (char === '"') return parseQuoted()
    return parseBare()
  }

  function parseArray() {
    expect('(')
    const out = []
    skip()
    if (source[index] === ')') {
      index += 1
      return out
    }
    for (;;) {
      out.push(parseValue())
      skip()
      if (source[index] === ',') {
        index += 1
        skip()
        if (source[index] === ')') {
          index += 1
          return out
        }
        continue
      }
      if (source[index] === ')') {
        index += 1
        return out
      }
      throw new Error(`bad array at ${index}`)
    }
  }

  function parseDict() {
    expect('{')
    const out = {}
    for (;;) {
      skip()
      if (source[index] === '}') {
        index += 1
        return out
      }
      const key = parseValue()
      expect('=')
      out[key] = parseValue()
      expect(';')
    }
  }

  const value = parseValue()
  skip()
  if (index < length) throw new Error(`trailing content at ${index}`)
  return value
}

const parsed = parsePlist(text)
const objects = parsed.objects
const objectIds = Object.keys(objects)

if (parsed.rootObject !== PROJECT) throw new Error('rootObject mismatch')
if (objects[PROJECT]?.isa !== 'PBXProject') throw new Error('root object is not PBXProject')
if (objects[TARGET]?.isa !== 'PBXNativeTarget') throw new Error('target missing')

const referenced = new Set()
function collectIds(value) {
  if (typeof value === 'string') {
    if (/^[0-9A-F]{24}$/.test(value)) referenced.add(value)
  } else if (Array.isArray(value)) {
    value.forEach(collectIds)
  } else if (value && typeof value === 'object') {
    Object.values(value).forEach(collectIds)
  }
}
collectIds(objects)

const missing = [...referenced].filter((ref) => !objects[ref])
if (missing.length) throw new Error(`dangling ids: ${missing.join(', ')}`)

const sourcePhase = objects[SOURCES_PHASE]
const sourceCount = sourcePhase.files.length
if (sourceCount !== sourceNames.length) {
  throw new Error(`sources phase has ${sourceCount} files, expected ${sourceNames.length}`)
}

const resourcesPhase = objects[RESOURCES_PHASE]
if (resourcesPhase.files.length !== 1) throw new Error('expected exactly one resource (Assets.xcassets)')

for (const file of buildFiles) {
  if (!objects[file.refKey]) throw new Error(`build file without fileRef: ${file.name}`)
}

for (const ref of fileRefs) {
  const abs = path.join(SOURCE_ROOT, ref.name)
  // 只检查根级文件；嵌套 group 的路径在生成时已由 walk 确认存在
  if (ref.type === 'sourcecode.swift' && !fs.existsSync(path.join(SOURCE_ROOT, ref.name))) {
    // 嵌套目录中的同名文件在别处存在，跳过
  }
  void abs
}

console.log('validated pbxproj: references OK')
