import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["swatch", "text"]

  connect() {
    this.syncToText()
  }

  syncToText() {
    this.textTarget.value = this.swatchTarget.value.toUpperCase()
  }

  syncToSwatch() {
    let v = this.textTarget.value.trim()
    if (v && !v.startsWith("#")) v = "#" + v
    if (/^#[0-9A-Fa-f]{6}$/.test(v)) {
      this.swatchTarget.value = v
      this.textTarget.setCustomValidity("")
    } else {
      this.textTarget.setCustomValidity("Geçersiz HEX (örn. #22C55E)")
    }
  }
}
