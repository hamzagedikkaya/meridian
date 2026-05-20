import { Controller } from "@hotwired/stimulus"

// Vim-style "g <letter>" navigation shortcuts.
// g d → dashboard, g f → finance, g t → todos, g h → habits,
// g c → calendar, g j → journal, g g → goals
const ROUTES = {
  d: "/",
  f: "/finance",
  t: "/todos",
  h: "/habits",
  c: "/calendar",
  j: "/journal",
  g: "/goals"
}

export default class extends Controller {
  connect() {
    this.waitingForLetter = false
    this.timeout = null
    this.boundHandler = this.handle.bind(this)
    document.addEventListener("keydown", this.boundHandler)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandler)
    if (this.timeout) clearTimeout(this.timeout)
  }

  handle(event) {
    if (this.isTyping(event.target)) return
    if (event.metaKey || event.ctrlKey || event.altKey) return

    if (this.waitingForLetter) {
      const target = ROUTES[event.key.toLowerCase()]
      this.waitingForLetter = false
      if (this.timeout) clearTimeout(this.timeout)
      if (target) { event.preventDefault(); window.location.href = target }
    } else if (event.key === "g") {
      this.waitingForLetter = true
      this.timeout = setTimeout(() => { this.waitingForLetter = false }, 800)
    }
  }

  isTyping(target) {
    return target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable)
  }
}
