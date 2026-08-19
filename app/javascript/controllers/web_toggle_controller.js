import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["box"]

  connect() {
    const saved = localStorage.getItem("kura.web")
    if (this.hasBoxTarget && saved !== null) this.boxTarget.checked = saved === "1"
  }

  persist() {
    if (!this.hasBoxTarget) return
    localStorage.setItem("kura.web", this.boxTarget.checked ? "1" : "0")
  }
}
