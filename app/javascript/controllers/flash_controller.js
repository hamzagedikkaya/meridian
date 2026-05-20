import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["root"]

  connect() {
    this.timer = setTimeout(() => this.dismiss(), 5000)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  dismiss() {
    if (this.timer) clearTimeout(this.timer)
    const el = this.hasRootTarget ? this.rootTarget : this.element
    el.style.transition = "opacity 0.2s ease-out, transform 0.2s ease-out"
    el.style.opacity = "0"
    el.style.transform = "translateY(-4px)"
    setTimeout(() => el.remove(), 220)
  }
}
