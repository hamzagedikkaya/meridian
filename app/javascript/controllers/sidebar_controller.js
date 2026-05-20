import { Controller } from "@hotwired/stimulus"

// Collapsible sidebar — persists state in localStorage.
export default class extends Controller {
  static values = { collapsed: Boolean }

  connect() {
    const stored = localStorage.getItem("meridian-sidebar-collapsed")
    if (stored === "true") {
      this.element.classList.add("w-16")
      this.element.classList.remove("w-60")
    }
  }

  toggle() {
    const isCollapsed = this.element.classList.contains("w-16")
    if (isCollapsed) {
      this.element.classList.remove("w-16")
      this.element.classList.add("w-60")
      localStorage.setItem("meridian-sidebar-collapsed", "false")
    } else {
      this.element.classList.add("w-16")
      this.element.classList.remove("w-60")
      localStorage.setItem("meridian-sidebar-collapsed", "true")
    }
    // NOT: Tam state senkronizasyonu için sayfa yeniden render etmek gerekir.
    // Şimdilik width-only toggle; Aşama 8'de tam server-side state'e taşınacak.
  }
}
