import { Controller } from "@hotwired/stimulus"

// Replaces Turbo's default window.confirm() with a styled in-app dialog.
// Registered via Turbo.setConfirmMethod on connect, so EVERY element carrying
// data-turbo-confirm (all the delete buttons, etc.) routes through here — no
// per-call-site changes needed. Returns a Promise<boolean> that Turbo awaits.
export default class extends Controller {
  static targets = ["backdrop", "dialog", "message", "confirmButton"]
  static values = { confirmLabel: String, deleteLabel: String }

  connect() {
    this.resolver = null
    this.onKeydown = (e) => this.handleKeydown(e)
    document.addEventListener("keydown", this.onKeydown)
    window.Turbo?.setConfirmMethod((message, formElement, submitter) => this.ask(message, formElement, submitter))
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  ask(message, formElement, submitter) {
    this.messageTarget.textContent = message || ""
    this.styleConfirmButton(this.isDelete(formElement, submitter))
    this.open()
    return new Promise((resolve) => { this.resolver = resolve })
  }

  // Destructive (delete) actions get a red confirm button labelled "Delete";
  // everything else gets the neutral accent button labelled "Confirm".
  styleConfirmButton(destructive) {
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

  open() {
    this.backdropTarget.classList.remove("hidden")
    requestAnimationFrame(() => this.confirmButtonTarget.focus())
  }

  handleKeydown(e) {
    if (this.backdropTarget.classList.contains("hidden")) return
    if (e.key === "Escape") { e.preventDefault(); this.cancel() }
    else if (e.key === "Enter") { e.preventDefault(); this.confirm() }
  }

  // Backdrop click cancels; clicks inside the dialog bubble up to the backdrop
  // only if they ARE the backdrop, so guard on the event target.
  backdrop(e) { if (e.target === this.backdropTarget) this.cancel() }

  confirm() { this.settle(true) }
  cancel() { this.settle(false) }

  settle(value) {
    this.backdropTarget.classList.add("hidden")
    const resolve = this.resolver
    this.resolver = null
    resolve?.(value)
  }
}
