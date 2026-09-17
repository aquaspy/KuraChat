import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "input" ]

  connect() {
    this.saved = this.inputTarget.value
    this.submitting = false
    this.dirty = false
  }

  schedule() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.save(), 800)
  }

  save() {
    clearTimeout(this.timer)
    if (this.inputTarget.value === this.saved) return
    if (this.submitting) {
      this.dirty = true
      return
    }
    this.saved = this.inputTarget.value
    this.element.requestSubmit()
  }

  sync() {
    this.saved = this.inputTarget.value
    this.dirty = false
  }

  start() {
    this.submitting = true
  }

  end() {
    this.submitting = false
    if (this.dirty && this.inputTarget.value !== this.saved) {
      this.dirty = false
      this.save()
    } else {
      this.dirty = false
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
