// Marks OCaml attributes ([@x], [@@x], [@@@x]) in highlighted code so the
// theme can set them apart: they are what a reader of Kre code looks for.

type Node = { type: string; value?: string; tagName?: string; properties?: Record<string, unknown>; children?: Node[] }

const text = (node: Node): string =>
  node.type === 'text' ? node.value ?? '' : (node.children ?? []).map(text).join('')

const ranges = (line: string): [number, number][] => {
  const found: [number, number][] = []
  for (let start = 0; start < line.length; start++) {
    if (line[start] !== '[' || line[start + 1] !== '@') continue
    let depth = 0
    let end = start
    for (; end < line.length; end++) {
      if (line[end] === '[') depth++
      else if (line[end] === ']') {
        depth--
        if (depth === 0) break
      }
    }
    found.push([start, Math.min(end, line.length - 1)])
    start = end
  }
  return found
}

const addClass = (node: Node, name: string) => {
  const properties = (node.properties ??= {})
  const current = properties.class
  properties.class = [...(Array.isArray(current) ? current : current ? [String(current)] : []), name]
}

export const attributes = {
  name: 'kre-attributes',
  line(node: Node) {
    const spans = (node.children ?? []).filter((child) => child.type === 'element')
    const starts: number[] = []
    let line = ''
    for (const span of spans) {
      starts.push(line.length)
      line += text(span)
    }
    const found = ranges(line)
    if (found.length === 0) return
    spans.forEach((span, index) => {
      const from = starts[index]
      const to = from + text(span).length - 1
      const range = found.find(([start, end]) => from >= start && from <= end)
      if (!range) return
      addClass(span, 'kre-attr')
      if (from === range[0]) addClass(span, 'kre-attr-start')
      if (to >= range[1]) addClass(span, 'kre-attr-end')
    })
  }
}
