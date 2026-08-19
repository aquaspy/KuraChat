import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.stick = true
    this.element.addEventListener("scroll", this)
    this.scrollBottom()
  }

  disconnect() {
    this.element.removeEventListener("scroll", this)
  }

  handleEvent() {
    const el = this.element
    this.stick = el.scrollHeight - el.scrollTop - el.clientHeight < 64
  }

  appended() {
    if (this.stick) this.scrollBottom()
  }

  scrollBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
