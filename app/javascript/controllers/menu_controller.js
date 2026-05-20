import { Controller } from "@hotwired/stimulus"

// Simple dropdown menu — toggle panel + close on outside click.
export default class extends Controller {
  static targets = ["panel"]

  toggle(event) {
    event.stopPropagation()
    this.panelTarget.classList.toggle("hidden")
  }

  closeIfOutside(event) {
    if (!this.element.contains(event.target)) {
      this.panelTarget.classList.add("hidden")
    }
  }
}
