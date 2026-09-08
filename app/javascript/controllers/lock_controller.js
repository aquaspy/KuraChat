import { Controller } from "@hotwired/stimulus"

const IDLE_MS = 15 * 60 * 1000
const BACKGROUND_MS = 2 * 60 * 1000
const STORAGE_KEY = "kura_auto_lock"

export default class extends Controller {
  static values = {
    enabled: { type: Boolean, default: false },
    onLabel: { type: String, default: "" },
    offLabel: { type: String, default: "" }
  }

  connect() {
    this.hiddenAt = null
    this.syncFromStorage()
  }

  disconnect() {
    this.disarm()
  }

  enabledValueChanged() {
    if (this.enabledValue) this.arm()
    else this.disarm()
    this.refreshLabels()
  }

  togglePreference(event) {
    event.preventDefault()
    this.persist(!this.enabledValue)
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

  syncFromStorage() {
    const stored = window.localStorage.getItem(STORAGE_KEY)
    if (stored === "1" || stored === "0") {
      this.persist(stored === "1")
      return
    }
    this.persist(this.enabledValue)
  }

  persist(enabled) {
    const value = enabled ? "1" : "0"
    window.localStorage.setItem(STORAGE_KEY, value)
    this.writeCookie(value)
    this.enabledValue = enabled
  }

  writeCookie(value) {
    const secure = window.location.protocol === "https:" ? "; Secure" : ""
    document.cookie = `${STORAGE_KEY}=${value}; Path=/; Max-Age=31536000; SameSite=Lax${secure}`
  }

  refreshLabels() {
    if (!this.onLabelValue || !this.offLabelValue) return
    const label = this.enabledValue ? this.offLabelValue : this.onLabelValue
    this.element.querySelectorAll("[data-auto-lock-label]").forEach((el) => {
      el.textContent = label
    })
  }
}
