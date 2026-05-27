import { Controller } from "@hotwired/stimulus"

// Animates a numeric value from 0 to its end value when the element scrolls
// into view. Preserves the original formatted text as a no-JS fallback and
// re-formats on each frame so the number reads correctly during the tween.
//
// Usage:
//   <span data-controller="stat-counter"
//         data-stat-counter-end-value="24581.42"
//         data-stat-counter-format-value="money"
//         data-stat-counter-currency-symbol-value="₺"
//         data-stat-counter-locale-value="tr"
//         data-stat-counter-duration-value="900">₺24,581.42</span>
export default class extends Controller {
  static values = {
    end: Number,
    format: { type: String, default: "integer" },
    currencySymbol: { type: String, default: "" },
    symbolPosition: { type: String, default: "before" }, // before | after
    locale: { type: String, default: "tr" },
    duration: { type: Number, default: 900 },
    decimals: { type: Number, default: 0 }
  }

  connect() {
    if (this.prefersReducedMotion()) return

    this.originalText = this.element.textContent
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting && !this.started) {
          this.started = true
          this.animate()
          this.observer.disconnect()
        }
      })
    }, { threshold: 0.2 })
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  animate() {
    const start = performance.now()
    const tick = (now) => {
      const elapsed = now - start
      const t = Math.min(elapsed / this.durationValue, 1)
      const eased = 1 - Math.pow(1 - t, 3) // cubic-out
      const value = this.endValue * eased
      this.element.textContent = this.formatValue(value)
      if (t < 1) {
        this.frame = requestAnimationFrame(tick)
      } else {
        this.element.textContent = this.originalText
      }
    }
    this.frame = requestAnimationFrame(tick)
  }

  formatValue(n) {
    const decimals = this.formatValue === "integer" ? 0 : this.decimalsValue
    const formatted = n.toLocaleString(this.localeValue || "tr", {
      minimumFractionDigits: this.formatValue === "money" ? 2 : decimals,
      maximumFractionDigits: this.formatValue === "money" ? 2 : decimals
    })
    if (!this.currencySymbolValue) return formatted
    return this.symbolPositionValue === "after"
      ? `${formatted} ${this.currencySymbolValue}`
      : `${this.currencySymbolValue}${formatted}`
  }

  prefersReducedMotion() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
  }
}
