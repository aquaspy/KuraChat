import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit"]
  static values = { streaming: Boolean }

  connect() {
    this.sync()
    this.onOnline = () => this.sync()
    window.addEventListener("online", this.onOnline)
    window.addEventListener("offline", this.onOnline)
  }

  disconnect() {
    window.removeEventListener("online", this.onOnline)
    window.removeEventListener("offline", this.onOnline)
  }

  key(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      if (!this.blocked()) this.element.requestSubmit()
    }
  }

  resize() {
    if (!this.hasInputTarget) return
    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${Math.min(this.inputTarget.scrollHeight, 180)}px`
  }

  streamingValueChanged() {
    this.sync()
  }

  sync() {
    const off = this.blocked()
    if (this.hasInputTarget) this.inputTarget.disabled = off
    if (this.hasSubmitTarget) this.submitTarget.disabled = off
  }

  blocked() {
    return this.streamingValue || !navigator.onLine
  }
}
