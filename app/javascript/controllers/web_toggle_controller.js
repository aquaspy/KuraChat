import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["box"]
  static values = {
    locked: { type: Boolean, default: false },
    on: { type: Boolean, default: false },
    lockedOnHint: { type: String, default: "" },
    lockedOffHint: { type: String, default: "" }
  }

  connect() {
    if (this.lockedValue) {
      this.freeze(this.onValue)
      return
    }
    const saved = localStorage.getItem("kura.web")
    if (this.hasBoxTarget && saved !== null) this.boxTarget.checked = saved === "1"
    this.paint()
  }

  persist() {
    if (this.lockedValue) {
      this.freeze(this.onValue)
      return
    }
    if (!this.hasBoxTarget) return
    localStorage.setItem("kura.web", this.boxTarget.checked ? "1" : "0")
    this.paint()
  }

  lockAfterSend(event) {
    if (event.detail?.success === false) return
    if (this.lockedValue) return
    const on = this.hasBoxTarget ? this.boxTarget.checked : false
    this.lockedValue = true
    this.onValue = on
    this.freeze(on)
  }

  freeze(on) {
    if (!this.hasBoxTarget) return
    this.boxTarget.checked = on
    this.boxTarget.disabled = true
    this.boxTarget.setAttribute("aria-checked", String(on))
    const switchEl = this.element.querySelector(".web-switch")
    switchEl?.classList.add("is-locked")
    const hint = on ? this.lockedOnHintValue : this.lockedOffHintValue
    if (hint) {
      switchEl?.setAttribute("title", hint)
      this.boxTarget.setAttribute("aria-label", hint)
    }
    this.ensureHidden(on)
    this.paint()
  }

  ensureHidden(on) {
    let hidden = this.element.querySelector("input[type=hidden][name=web]")
    if (!hidden) {
      hidden = document.createElement("input")
      hidden.type = "hidden"
      hidden.name = "web"
      this.element.appendChild(hidden)
    }
    hidden.value = on ? "1" : "0"
  }

  paint() {
    if (!this.hasBoxTarget) return
    const on = this.boxTarget.checked
    this.boxTarget.setAttribute("aria-checked", String(on))
    this.element.querySelector(".web-switch")?.setAttribute("aria-pressed", String(on))
  }
}
