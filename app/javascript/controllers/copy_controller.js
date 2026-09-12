import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "label"]
  static values = { copied: String, idle: String }

  async copy() {
    const text = this.hasSourceTarget ? this.sourceTarget.value : ""
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.sourceTarget.focus()
      this.sourceTarget.select()
      document.execCommand("copy")
    }
    if (!this.hasLabelTarget) return
    this.labelTarget.textContent = this.copiedValue
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.labelTarget.textContent = this.idleValue
    }, 1400)
  }
}
