import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  query() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), 180)
  }

  flush() {
    clearTimeout(this.timer)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
