import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["box", "url", "status"]
  static values = { copied: String }

  open() {
    this.boxTarget.showModal()
    this.selectUrl()
  }

  close() {
    this.boxTarget.close()
  }

  backdrop(event) {
    if (event.target === this.boxTarget) this.close()
  }

  selectUrl() {
    if (this.hasUrlTarget) this.urlTarget.focus()
    if (this.hasUrlTarget) this.urlTarget.select()
  }

  async copy() {
    if (!this.hasUrlTarget) return
    const url = this.urlTarget.value
    try {
      await navigator.clipboard.writeText(url)
    } catch {
      this.selectUrl()
      document.execCommand("copy")
    }
    if (!this.hasStatusTarget) return
    this.statusTarget.hidden = false
    this.statusTarget.textContent = this.copiedValue
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { this.statusTarget.hidden = true }, 1400)
  }
}
