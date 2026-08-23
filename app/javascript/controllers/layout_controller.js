import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "menuButton"]

  connect() {
    this.syncViewport = () => {
      const vv = window.visualViewport
      const height = vv?.height ?? window.innerHeight
      const top = vv?.offsetTop ?? 0
      document.documentElement.style.setProperty("--vvh", `${Math.round(height)}px`)
      document.documentElement.style.setProperty("--vvt", `${Math.round(top)}px`)
    }
    this.syncViewport()
    window.visualViewport?.addEventListener("resize", this.syncViewport)
    window.visualViewport?.addEventListener("scroll", this.syncViewport)
    window.addEventListener("resize", this.syncViewport)

    this.onPointer = (event) => {
      if (this.hasMenuTarget && !this.menuTarget.hidden && !event.target.closest(".mobile-menu, [data-layout-target='menuButton']")) {
        this.closeMenu()
      }
    }
    document.addEventListener("pointerdown", this.onPointer)
  }

  disconnect() {
    window.visualViewport?.removeEventListener("resize", this.syncViewport)
    window.visualViewport?.removeEventListener("scroll", this.syncViewport)
    window.removeEventListener("resize", this.syncViewport)
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
