import { Controller } from "@hotwired/stimulus"

// Quick capture modal — opens with the "c" key.
// Text labels come from server-side i18n via data-*-value attributes.
export default class extends Controller {
  static values = {
    placeholder: { type: String, default: "Capture anything…" },
    hint:        { type: String, default: 'Numbers → transaction · "habit: name" → log · text → todo' },
    button:      { type: String, default: "Capture" }
  }

  connect() {
    this.boundKey = this.handleKey.bind(this)
    document.addEventListener("keydown", this.boundKey)
  }
  disconnect() { document.removeEventListener("keydown", this.boundKey); this.closeModal() }

  handleKey(e) {
    if (e.key === "c" && !(e.metaKey || e.ctrlKey || e.altKey) && !this.isTyping(e.target)) {
      e.preventDefault()
      this.open()
    } else if (e.key === "Escape" && this.modal) {
      this.closeModal()
    }
  }
  isTyping(t) { return t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable) }

  open() {
    if (this.modal) return
    this.modal = document.createElement("div")
    this.modal.className = "fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-start justify-center pt-24"
    this.modal.innerHTML = `
      <form action="/quick_captures" method="post" class="w-full max-w-lg bg-[var(--color-bg-elevated)] border border-[var(--color-border-default)] rounded-[var(--radius-md)] overflow-hidden shadow-2xl">
        <input type="hidden" name="authenticity_token" value="${this.csrfToken()}">
        <input type="text" name="text" autofocus placeholder="${this.escape(this.placeholderValue)}"
               class="w-full px-4 py-4 bg-transparent text-base text-[var(--color-fg-primary)] placeholder-[var(--color-fg-faint)] focus:outline-none">
        <div class="px-4 py-3 border-t border-[var(--color-border-subtle)] flex items-center justify-between gap-3">
          <p class="text-xs text-[var(--color-fg-muted)]">${this.escape(this.hintValue)}</p>
          <button type="submit" class="px-3 py-1.5 text-sm bg-[var(--color-accent-500)] hover:bg-[var(--color-accent-600)] text-[var(--color-bg-base)] rounded-[var(--radius-sm)] font-medium whitespace-nowrap">${this.escape(this.buttonValue)}</button>
        </div>
      </form>
    `
    document.body.appendChild(this.modal)
    this.modal.addEventListener("click", (e) => { if (e.target === this.modal) this.closeModal() })
  }

  closeModal() { if (this.modal) { this.modal.remove(); this.modal = null } }

  csrfToken() { return document.querySelector('meta[name="csrf-token"]')?.content || "" }

  escape(s) {
    const div = document.createElement("div")
    div.textContent = s
    return div.innerHTML
  }
}
