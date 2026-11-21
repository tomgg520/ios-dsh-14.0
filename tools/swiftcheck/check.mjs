// 用 tree-sitter 的 Swift 语法检查客户端源码（只做语法解析，不做类型检查）。
import fs from 'node:fs'
import path from 'node:path'
import { Parser, Language } from 'web-tree-sitter'

const HERE = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'))
const SOURCE_ROOT = path.resolve(HERE, '..', '..', 'DSHClient')
const WASM = path.join(HERE, 'node_modules', 'tree-sitter-wasms', 'out', 'tree-sitter-swift.wasm')

function collect(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) collect(full, out)
    else if (entry.name.endsWith('.swift')) out.push(full)
  }
  return out
}

await Parser.init()
const language = await Language.load(WASM)
const parser = new Parser()
parser.setLanguage(language)

const files = collect(SOURCE_ROOT).sort()
let failed = 0

for (const file of files) {
  const source = fs.readFileSync(file, 'utf8')
  const tree = parser.parse(source)
  const errors = []

  function walk(node) {
    if (node.type === 'ERROR' || node.isMissing) {
      errors.push(node)
      return
    }
    for (let i = 0; i < node.namedChildCount; i += 1) walk(node.namedChild(i))
  }
  walk(tree.rootNode)

  const relative = path.relative(SOURCE_ROOT, file)
  if (errors.length === 0) {
    console.log(`OK    ${relative}`)
  } else {
    failed += 1
    console.log(`FAIL  ${relative}`)
    for (const node of errors.slice(0, 6)) {
      const start = node.startPosition
      const text = source.slice(node.startIndex, Math.min(node.endIndex, node.startIndex + 120)).replace(/\n/g, '\\n')
      console.log(`      line ${start.row + 1}:${start.column + 1} ${node.type} ${JSON.stringify(text)}`)
    }
  }
}

console.log(`\n${files.length - failed}/${files.length} files parsed without errors`)
process.exit(failed === 0 ? 0 : 1)
