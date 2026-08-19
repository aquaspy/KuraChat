import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

const ORDER = ["system", "light", "dark"]
const LABEL = { system: "theme_system", light: "theme_light", dark: "theme_dark" }

export default class extends Controller {
  connect() {
    this.paint()
    this.media = window.matchMedia("(prefers-color-scheme: dark)")
    this.media.addEventListener("change", this)
  }

  disconnect() {
    this.media?.removeEventListener("change", this)
  }

  handleEvent() {
    this.paintMeta()
  }

  cycle(event) {
    event?.preventDefault()
    const current = document.documentElement.dataset.theme || "system"
    this.apply(ORDER[(ORDER.indexOf(current) + 1) % ORDER.length])
  }

  set(event) {
    event?.preventDefault()
    const theme = event.currentTarget.dataset.themeChoice
    if (ORDER.includes(theme)) this.apply(theme)
  }

  apply(theme) {
    localStorage.setItem("kura.theme", theme)
    document.documentElement.dataset.theme = theme
    this.paint()
  }

  paint() {
    const theme = document.documentElement.dataset.theme || "system"
    document.querySelectorAll("[data-theme-button]").forEach((el) => {
      el.title = `${t(LABEL[theme])} — ${t("theme_switch")}`
      el.dataset.themeState = theme
    })
    document.querySelectorAll("[data-theme-choice]").forEach((el) => {
      const on = el.dataset.themeChoice === theme
      el.classList.toggle("is-on", on)
      el.setAttribute("aria-pressed", String(on))
    })
    this.paintMeta()
  }

  paintMeta() {
    const theme = document.documentElement.dataset.theme || "system"
    const dark = theme === "dark" || (theme === "system" && this.media.matches)
    document.querySelector("meta[name='theme-color']")?.setAttribute("content", dark ? "#141311" : "#f4f0e8")
  }
}
