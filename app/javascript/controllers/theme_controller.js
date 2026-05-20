import { Controller } from "@hotwired/stimulus"

// Toggles dark/light mode and persists preference in localStorage.
// Connected on <body data-controller="theme">.
export default class extends Controller {
  connect() {
    const stored = localStorage.getItem("meridian-theme")
    if (stored) {
      this.apply(stored)
    } else {
      this.apply("dark") // dark-first default
    }
  }

  toggle() {
    const current = document.documentElement.classList.contains("dark") ? "dark" : "light"
    const next = current === "dark" ? "light" : "dark"
    this.apply(next)
    localStorage.setItem("meridian-theme", next)
  }

  apply(mode) {
    const html = document.documentElement
    if (mode === "dark") {
      html.classList.add("dark")
      html.classList.remove("light")
    } else {
      html.classList.add("light")
      html.classList.remove("dark")
    }
  }
}
