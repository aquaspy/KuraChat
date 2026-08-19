const strings = readTable()

export function t(key) {
  return strings[key] ?? key
}

function readTable() {
  const node = document.getElementById("i18n")
  if (!node) return {}
  try {
    return JSON.parse(node.textContent)
  } catch {
    return {}
  }
}
