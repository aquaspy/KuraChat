import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit"]
  static values = { streaming: Boolean }

  connect() {
    this.sending = false
    this.sync()
    this.resize()
    this.tryFocus()
    requestAnimationFrame(() => this.tryFocus())
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

  start() {
    if (!this.hasInputTarget) return
    this.draft = this.inputTarget.value
    this.sending = true
    this.sync()
    this.echo(this.draft)
    this.inputTarget.value = ""
    this.inputTarget.style.height = ""
  }

  sent(event) {
    this.sending = false
    this.sync()
    if (event.detail?.success === false) {
      this.removeEcho()
      if (this.hasInputTarget && this.draft != null && !this.inputTarget.value) {
        this.inputTarget.value = this.draft
        this.resize()
      }
      return
    }
    if (!this.hasInputTarget) return
    if (this.narrow()) this.inputTarget.blur()
    else this.inputTarget.focus()
  }

  streamingValueChanged() {
    this.sync()
  }

  sync() {
    if (this.hasInputTarget) this.inputTarget.disabled = this.streamingValue || !navigator.onLine
    if (this.hasSubmitTarget) this.submitTarget.disabled = this.blocked()
  }

  blocked() {
    return this.sending || this.streamingValue || !navigator.onLine
  }

  tryFocus() {
    if (!this.hasInputTarget || this.blocked()) return
    if (!this.inputTarget.hasAttribute("autofocus")) return
    this.inputTarget.focus({ preventScroll: true })
  }

  narrow() {
    return window.matchMedia("(max-width: 860px)").matches
  }

  echo(text) {
    const transcript = document.getElementById("transcript")
    const value = text == null ? "" : text.toString()
    if (!transcript || !value.trim()) return
    let node = document.getElementById("msg-echo")
    if (!node) {
      node = document.createElement("article")
      node.id = "msg-echo"
      node.className = "msg msg-user is-echo"
      const body = document.createElement("div")
      body.className = "msg-body"
      node.appendChild(body)
      transcript.appendChild(node)
    }
    node.querySelector(".msg-body").textContent = value
    transcript.scrollTop = transcript.scrollHeight
  }

  removeEcho() {
    document.getElementById("msg-echo")?.remove()
  }
}
