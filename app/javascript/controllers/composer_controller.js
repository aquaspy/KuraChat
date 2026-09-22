import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit", "file", "chips"]
  static values = { streaming: Boolean, maxImages: Number, removeLabel: String }

  // Field initializers run at construction: Stimulus fires value-changed
  // callbacks (sync -> hasFile) before connect(), so this state must
  // already exist. connect() still resets it on every reconnect.
  sending = false
  chosen = []
  previewUrls = []

  connect() {
    this.sending = false
    this.chosen = []
    this.previewUrls = []
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
    this.revokePreviews()
  }

  key(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      if (!this.blocked()) this.element.requestSubmit()
    }
  }

  paste(event) {
    if (!this.hasFileTarget) return
    const files = [...(event.clipboardData?.items || [])]
      .filter((entry) => entry.type.startsWith("image/"))
      .map((entry) => entry.getAsFile())
      .filter(Boolean)
    if (files.length === 0) return

    event.preventDefault()
    this.addFiles(files)
  }

  picked() {
    if (!this.hasFileTarget) return
    // A dialog pick replaces the input, so merge it into the kept files.
    const fresh = [...this.fileTarget.files]
    this.fileTarget.value = ""
    this.addFiles(fresh)
  }

  removeImage(event) {
    const index = Number(event.params?.index)
    if (!Number.isInteger(index)) return
    this.chosen.splice(index, 1)
    this.writeFiles()
    this.renderChips()
    this.sync()
  }

  clearImage() {
    this.chosen = []
    this.writeFiles()
    this.renderChips()
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
    const previews = this.chosen.map((file) => URL.createObjectURL(file))
    this.echo(this.draft, previews)
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
    if (this.hasInputTarget) this.inputTarget.disabled = this.streamingValue
    if (this.hasFileTarget) this.fileTarget.disabled = this.streamingValue
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
    return this.chosen.length > 0
  }

  tryFocus() {
    if (!this.hasInputTarget || this.sending || this.streamingValue) return
    if (!this.inputTarget.hasAttribute("autofocus")) return
    this.inputTarget.focus({ preventScroll: true })
  }

  narrow() {
    return window.matchMedia("(max-width: 860px)").matches
  }

  addFiles(files) {
    const max = this.maxImagesValue > 0 ? this.maxImagesValue : 4
    this.chosen = [...this.chosen, ...files].slice(0, max)
    this.writeFiles()
    this.renderChips()
    this.sync()
  }

  writeFiles() {
    if (!this.hasFileTarget) return
    const transfer = new DataTransfer()
    this.chosen.forEach((file) => transfer.items.add(file))
    this.fileTarget.files = transfer.files
  }

  echo(text, imageUrls) {
    const transcript = document.getElementById("transcript")
    const value = text == null ? "" : text.toString()
    const urls = imageUrls.filter(Boolean)
    if (!transcript || (!value.trim() && urls.length === 0)) return
    let node = document.getElementById("msg-echo")
    if (!node) {
      node = document.createElement("article")
      node.id = "msg-echo"
      node.className = "msg msg-user is-echo"
      transcript.appendChild(node)
    }
    node.replaceChildren()
    urls.forEach((url) => {
      const wrap = document.createElement("div")
      wrap.className = "msg-image"
      const img = document.createElement("img")
      img.src = url
      img.alt = ""
      wrap.appendChild(img)
      node.appendChild(wrap)
    })
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

  renderChips() {
    if (!this.hasChipsTarget) return
    this.revokePreviews()
    this.chipsTarget.replaceChildren()
    this.chosen.forEach((file, index) => {
      const url = URL.createObjectURL(file)
      this.previewUrls.push(url)
      const chip = document.createElement("div")
      chip.className = "composer-chip"
      const img = document.createElement("img")
      img.alt = ""
      img.src = url
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "composer-chip-x"
      remove.textContent = "×"
      remove.dataset.action = "composer#removeImage"
      remove.dataset.composerIndexParam = String(index)
      if (this.hasRemoveLabelValue) remove.setAttribute("aria-label", this.removeLabelValue)
      chip.append(img, remove)
      this.chipsTarget.appendChild(chip)
    })
    this.chipsTarget.hidden = this.chosen.length === 0
  }

  revokePreviews() {
    this.previewUrls.forEach((url) => URL.revokeObjectURL(url))
    this.previewUrls = []
  }
}
