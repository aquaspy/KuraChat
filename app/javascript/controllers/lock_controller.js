import { Controller } from "@hotwired/stimulus"

const IDLE_MS = 15 * 60 * 1000
const BACKGROUND_MS = 2 * 60 * 1000

export default class extends Controller {
  static values = { enabled: { type: Boolean, default: false } }

  connect() {
    this.hiddenAt = null
  }

  disconnect() {
    this.disarm()
  }

  enabledValueChanged() {
    if (this.enabledValue) this.arm()
    else this.disarm()
  }

  arm() {
    this.disarm()
    document.addEventListener("pointerdown", this)
    document.addEventListener("keydown", this)
    document.addEventListener("visibilitychange", this)
    this.bump()
  }

  disarm() {
    clearTimeout(this.timer)
    document.removeEventListener("pointerdown", this)
    document.removeEventListener("keydown", this)
    document.removeEventListener("visibilitychange", this)
  }

  handleEvent(event) {
    if (!this.enabledValue) return
    if (event.type === "visibilitychange") {
      if (document.hidden) {
        this.hiddenAt = Date.now()
      } else if (this.hiddenAt && Date.now() - this.hiddenAt > BACKGROUND_MS) {
        this.lock()
      }
      return
    }
    this.bump()
  }

  bump() {
    if (!this.enabledValue) return
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.lock(), IDLE_MS)
  }

  lock() {
    document.getElementById("lock-now-form")?.requestSubmit()
  }
}
