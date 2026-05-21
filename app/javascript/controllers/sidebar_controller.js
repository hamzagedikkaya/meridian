import { Controller } from "@hotwired/stimulus"

// Collapsible sidebar — toggles a `.sidebar-collapsed` class on the aside.
// CSS in application.tailwind.css hides every `.sidebar-label` inside a
// collapsed sidebar, so the icon-only rail appears without a page reload.
// Persists state in localStorage.
const KEY = "meridian-sidebar-collapsed"

export default class extends Controller {
  connect() {
    if (localStorage.getItem(KEY) === "true") {
      this.collapse()
    }
  }

  toggle() {
    if (this.element.classList.contains("sidebar-collapsed")) {
      this.expand()
    } else {
      this.collapse()
    }
  }

  collapse() {
    this.element.classList.add("sidebar-collapsed", "w-16")
    this.element.classList.remove("w-60")
    localStorage.setItem(KEY, "true")
  }

  expand() {
    this.element.classList.remove("sidebar-collapsed", "w-16")
    this.element.classList.add("w-60")
    localStorage.setItem(KEY, "false")
  }
}
