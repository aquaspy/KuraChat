import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "menuButton"]

  connect() {
    this.onPointer = (event) => {
      if (this.hasMenuTarget && !this.menuTarget.hidden && !event.target.closest(".mobile-menu, [data-layout-target='menuButton']")) {
        this.closeMenu()
      }
    }
    document.addEventListener("pointerdown", this.onPointer)
  }

  disconnect() {
    document.removeEventListener("pointerdown", this.onPointer)
  }

  toggleMenu() {
    if (!this.hasMenuTarget) return
    this.menuTarget.hidden = !this.menuTarget.hidden
    if (this.hasMenuButtonTarget) this.menuButtonTarget.setAttribute("aria-expanded", String(!this.menuTarget.hidden))
  }

  closeMenu() {
    if (this.hasMenuTarget) this.menuTarget.hidden = true
    if (this.hasMenuButtonTarget) this.menuButtonTarget.setAttribute("aria-expanded", "false")
  }
}
