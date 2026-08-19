import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["box", "destroy", "message"]

  open(event) {
    const trigger = event.currentTarget
    const url = trigger.dataset.url
    const message = trigger.dataset.message
    if (url && this.hasDestroyTarget) this.destroyTarget.href = url
    if (message && this.hasMessageTarget) this.messageTarget.textContent = message
    this.boxTarget.showModal()
  }

  close() {
    this.boxTarget.close()
  }

  backdrop(event) {
    if (event.target === this.boxTarget) this.close()
  }
}
