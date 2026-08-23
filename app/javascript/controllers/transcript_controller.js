import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.stick = true
    this.element.addEventListener("scroll", this)
    this.onViewport = () => { if (this.stick) this.scrollBottom() }
    window.visualViewport?.addEventListener("resize", this.onViewport)
    this.scrollBottom()
  }

  disconnect() {
    this.element.removeEventListener("scroll", this)
    window.visualViewport?.removeEventListener("resize", this.onViewport)
  }

  handleEvent() {
    const el = this.element
    this.stick = el.scrollHeight - el.scrollTop - el.clientHeight < 64
  }

  appended(event) {
    const render = event.detail?.render
    if (!render) {
      if (this.stick) this.scrollBottom()
      return
    }
    event.detail.render = (streamElement) => {
      const result = render(streamElement)
      return Promise.resolve(result).then(() => {
        document.getElementById("msg-echo")?.remove()
        if (this.stick) this.scrollBottom()
        return result
      })
    }
  }

  scrollBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
