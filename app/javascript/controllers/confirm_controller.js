import { Controller } from "@hotwired/stimulus"

// Replaces Turbo's default window.confirm() with a styled, accessible in-app
// dialog. Registered via Turbo.setConfirmMethod on connect, so EVERY element
// carrying data-turbo-confirm (all the delete buttons, etc.) routes through
// here — no per-call-site changes needed. Returns a Promise<boolean>.
//
// Follows destructive-action best practice: a familiar trash icon + a red,
// verb-labelled button (not colour alone); the SAFE choice (Cancel) takes
// initial focus so a stray Enter never confirms a delete; focus is trapped
// while open and returned to the trigger on close.
const TRASH_ICON = `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path><line x1="10" y1="11" x2="10" y2="17"></line><line x1="14" y1="11" x2="14" y2="17"></line></svg>`
const ALERT_ICON = `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>`

export default class extends Controller {
  static targets = ["backdrop", "dialog", "message", "icon", "confirmButton", "cancelButton"]
  static values = { confirmLabel: String, deleteLabel: String }

  connect() {
    this.resolver = null
    this.trigger = null
    this.onKeydown = (e) => this.handleKeydown(e)
    document.addEventListener("keydown", this.onKeydown)
    window.Turbo?.setConfirmMethod((message, formElement, submitter) => this.ask(message, formElement, submitter))
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    this.unlockScroll()
  }

  ask(message, formElement, submitter) {
    const destructive = this.isDelete(formElement, submitter)
    this.messageTarget.textContent = message || ""
    this.applyVariant(destructive)
    this.trigger = document.activeElement
    this.open(destructive)
    return new Promise((resolve) => { this.resolver = resolve })
  }

  // Destructive (delete) → trash icon, red "Delete" button. Otherwise → info
  // icon, accent "Confirm" button.
  applyVariant(destructive) {
    this.iconTarget.innerHTML = destructive ? TRASH_ICON : ALERT_ICON
    this.iconTarget.classList.toggle("text-[var(--color-expense)]", destructive)
    this.iconTarget.classList.toggle("text-[var(--color-accent-400)]", !destructive)

    const base = "px-4 py-2 text-sm font-medium rounded-[var(--radius-sm)] cursor-pointer "
    this.confirmButtonTarget.className = base + (destructive
      ? "bg-[var(--color-expense)] text-white hover:opacity-90"
      : "bg-[var(--color-accent-500)] hover:bg-[var(--color-accent-600)] text-[var(--color-bg-base)]")
    this.confirmButtonTarget.textContent = destructive ? this.deleteLabelValue : this.confirmLabelValue
  }

  isDelete(formElement, submitter) {
    const method = submitter?.getAttribute?.("formmethod") ||
                   formElement?.querySelector?.('input[name="_method"]')?.value ||
                   formElement?.getAttribute?.("method") || ""
    return method.toLowerCase() === "delete"
  }

  open(destructive) {
    this.backdropTarget.classList.remove("hidden")
    this.lockScroll()
    // Safe-by-default: a delete focuses Cancel so Enter can't confirm it; a
    // non-destructive confirm focuses its primary button for convenience.
    const initial = destructive ? this.cancelButtonTarget : this.confirmButtonTarget
    requestAnimationFrame(() => initial.focus())
  }

  handleKeydown(e) {
    if (this.isClosed) return
    if (e.key === "Escape") {
      e.preventDefault()
      this.cancel()
    } else if (e.key === "Tab") {
      this.trapFocus(e)
    }
  }

  // Keep Tab within the dialog's two buttons.
  trapFocus(e) {
    const focusables = [this.cancelButtonTarget, this.confirmButtonTarget]
    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault()
      first.focus()
    }
  }

  backdrop(e) { if (e.target === this.backdropTarget) this.cancel() }

  confirm() { this.settle(true) }
  cancel() { this.settle(false) }

  settle(value) {
    this.backdropTarget.classList.add("hidden")
    this.unlockScroll()
    // Return focus to whatever opened the dialog (the delete button) for
    // keyboard/screen-reader users, when it's still on the page.
    if (this.trigger?.isConnected) this.trigger.focus()
    this.trigger = null
    const resolve = this.resolver
    this.resolver = null
    resolve?.(value)
  }

  get isClosed() {
    return this.backdropTarget.classList.contains("hidden")
  }

  lockScroll() { document.documentElement.style.overflow = "hidden" }
  unlockScroll() { document.documentElement.style.overflow = "" }
}
