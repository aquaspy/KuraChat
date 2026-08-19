import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["box"]

  connect() {
    const saved = localStorage.getItem("kura.web")
    if (this.hasBoxTarget && saved !== null) this.boxTarget.checked = saved === "1"
    this.paint()
  }

  persist() {
    if (!this.hasBoxTarget) return
    localStorage.setItem("kura.web", this.boxTarget.checked ? "1" : "0")
    this.paint()
  }

  paint() {
    if (!this.hasBoxTarget) return
    const on = this.boxTarget.checked
    this.boxTarget.setAttribute("aria-checked", String(on))
    this.element.querySelector(".web-switch")?.setAttribute("aria-pressed", String(on))
  }
}
