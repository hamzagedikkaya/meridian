import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.boundKeydown = this.handleGlobalKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
    this.closeModal()
  }

  handleGlobalKeydown(event) {
    // Cmd/Ctrl + K
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.open()
    } else if (event.key === "/" && !this.isTyping(event.target)) {
      event.preventDefault()
      this.open()
    } else if (event.key === "Escape" && this.modal) {
      this.closeModal()
    }
  }

  isTyping(target) {
    return target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable)
  }

  open() {
    if (this.modal) return
    this.modal = this.buildModal()
    document.body.appendChild(this.modal)
    this.input = this.modal.querySelector("input[type='search']")
    this.list  = this.modal.querySelector("[data-results]")
    this.input.focus()
    this.input.addEventListener("input", () => this.search())
    this.modal.addEventListener("click", (e) => { if (e.target === this.modal) this.closeModal() })
    document.addEventListener("keydown", this.navHandler = (e) => this.handleNav(e))
  }

  closeModal() {
    if (!this.modal) return
    this.modal.remove()
    this.modal = null
    document.removeEventListener("keydown", this.navHandler)
  }

  async search() {
    const q = this.input.value.trim()
    if (q.length < 2) { this.list.innerHTML = `<p class="px-4 py-3 text-sm text-[var(--color-fg-muted)]">Type at least 2 characters…</p>`; return }
    const res = await fetch(`/search?q=${encodeURIComponent(q)}`, { headers: { "Accept": "application/json" } })
    const data = await res.json()
    if (data.results.length === 0) {
      this.list.innerHTML = `<p class="px-4 py-3 text-sm text-[var(--color-fg-muted)]">No results.</p>`
    } else {
      this.list.innerHTML = data.results.map((r, i) => `
        <a href="${r.url}" data-idx="${i}" class="block px-4 py-2.5 hover:bg-[var(--color-bg-hover)] focus:bg-[var(--color-bg-hover)] outline-none">
          <div class="flex items-center justify-between gap-2">
            <span class="text-sm">${this.escape(r.title)}</span>
            <span class="text-xs text-[var(--color-fg-faint)] uppercase tracking-wider">${r.type}</span>
          </div>
          <p class="text-xs text-[var(--color-fg-muted)] mt-0.5">${this.escape(r.subtitle || "")}</p>
        </a>`).join("")
    }
  }

  escape(s) {
    const div = document.createElement("div")
    div.textContent = s
    return div.innerHTML
  }

  handleNav(event) {
    const items = Array.from(this.list.querySelectorAll("a"))
    if (items.length === 0) return
    const current = document.activeElement.closest("a[data-idx]")
    let idx = current ? parseInt(current.dataset.idx) : -1
    if (event.key === "ArrowDown") {
      event.preventDefault()
      const next = items[Math.min(idx + 1, items.length - 1)]
      next?.focus()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      if (idx <= 0) { this.input.focus(); return }
      items[idx - 1]?.focus()
    } else if (event.key === "Enter" && current) {
      current.click()
    }
  }

  buildModal() {
    const modal = document.createElement("div")
    modal.className = "fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-start justify-center pt-24"
    modal.innerHTML = `
      <div class="w-full max-w-xl bg-[var(--color-bg-elevated)] border border-[var(--color-border-default)] rounded-[var(--radius-md)] overflow-hidden shadow-2xl">
        <div class="border-b border-[var(--color-border-subtle)] px-4 py-3 flex items-center gap-2">
          <span class="text-[var(--color-fg-muted)]">⌕</span>
          <input type="search" placeholder="Search transactions, todos, journal, events, goals…"
                 class="flex-1 bg-transparent text-base text-[var(--color-fg-primary)] placeholder-[var(--color-fg-faint)] focus:outline-none">
          <kbd class="text-xs text-[var(--color-fg-muted)] px-1.5 py-0.5 bg-[var(--color-bg-overlay)] rounded">Esc</kbd>
        </div>
        <div data-results class="max-h-96 overflow-y-auto">
          <p class="px-4 py-3 text-sm text-[var(--color-fg-muted)]">Type to search…</p>
        </div>
      </div>
    `
    return modal
  }
}
