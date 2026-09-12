import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit", "file", "chip", "thumb"]
  static values = { streaming: Boolean }

  connect() {
    this.sending = false
    this.previewUrl = null
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
    this.revokePreview()
  }

  key(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      if (!this.blocked()) this.element.requestSubmit()
    }
  }

  paste(event) {
    const item = [...(event.clipboardData?.items || [])].find((entry) => entry.type.startsWith("image/"))
    if (!item || !this.hasFileTarget) return

    const file = item.getAsFile()
    if (!file) return

    event.preventDefault()
    const transfer = new DataTransfer()
    transfer.items.add(file)
    this.fileTarget.files = transfer.files
    this.picked()
  }

  picked() {
    this.showChip()
    this.sync()
  }

  clearImage() {
    if (this.hasFileTarget) this.fileTarget.value = ""
    this.hideChip()
    this.sync()
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
    const file = this.hasFileTarget ? this.fileTarget.files?.[0] : null
    const preview = file ? URL.createObjectURL(file) : null
    this.echo(this.draft, preview)
    this.inputTarget.value = ""
    this.inputTarget.style.height = ""
    this.clearImage()
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
    if (this.hasFileTarget) this.fileTarget.disabled = this.streamingValue || !navigator.onLine
    if (this.hasSubmitTarget) this.submitTarget.disabled = this.blocked()
  }

  blocked() {
    return this.sending || this.streamingValue || !navigator.onLine || this.empty()
  }

  empty() {
    const text = this.hasInputTarget ? this.inputTarget.value.trim() : ""
    return !text && !this.hasFile()
  }

  hasFile() {
    return this.hasFileTarget && this.fileTarget.files?.length > 0
  }

  tryFocus() {
    if (!this.hasInputTarget || this.sending || this.streamingValue || !navigator.onLine) return
    if (!this.inputTarget.hasAttribute("autofocus")) return
    this.inputTarget.focus({ preventScroll: true })
  }

  narrow() {
    return window.matchMedia("(max-width: 860px)").matches
  }

  echo(text, imageUrl) {
    const transcript = document.getElementById("transcript")
    const value = text == null ? "" : text.toString()
    if (!transcript || (!value.trim() && !imageUrl)) return
    let node = document.getElementById("msg-echo")
    if (!node) {
      node = document.createElement("article")
      node.id = "msg-echo"
      node.className = "msg msg-user is-echo"
      transcript.appendChild(node)
    }
    node.replaceChildren()
    if (imageUrl) {
      const wrap = document.createElement("div")
      wrap.className = "msg-image"
      const img = document.createElement("img")
      img.src = imageUrl
      img.alt = ""
      wrap.appendChild(img)
      node.appendChild(wrap)
    }
    if (value.trim()) {
      const body = document.createElement("div")
      body.className = "msg-body"
      body.textContent = value
      node.appendChild(body)
    }
    transcript.scrollTop = transcript.scrollHeight
  }

  removeEcho() {
    document.getElementById("msg-echo")?.remove()
  }

  showChip() {
    const file = this.hasFileTarget ? this.fileTarget.files?.[0] : null
    if (!file || !this.hasChipTarget || !this.hasThumbTarget) return
    this.revokePreview()
    this.previewUrl = URL.createObjectURL(file)
    this.thumbTarget.src = this.previewUrl
    this.chipTarget.hidden = false
  }

  hideChip() {
    this.revokePreview()
    if (this.hasThumbTarget) this.thumbTarget.removeAttribute("src")
    if (this.hasChipTarget) this.chipTarget.hidden = true
  }

  revokePreview() {
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
