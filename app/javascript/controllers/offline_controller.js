import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["banner"]

  connect() {
    this.paint()
    this.onOnline = () => this.paint()
    window.addEventListener("online", this.onOnline)
    window.addEventListener("offline", this.onOnline)
  }

  disconnect() {
    window.removeEventListener("online", this.onOnline)
    window.removeEventListener("offline", this.onOnline)
  }

  paint() {
    if (this.hasBannerTarget) this.bannerTarget.hidden = navigator.onLine
  }
}
