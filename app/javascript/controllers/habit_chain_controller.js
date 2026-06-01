import { Controller } from "@hotwired/stimulus"

// Animates a habit chain SVG into view: each <g class="chain-link"> snaps in
// with a stagger when the chain scrolls into the viewport. Today-pending
// links get a subtle pulse so the user knows to act. Honours
// prefers-reduced-motion by skipping animation entirely.
//
// The chain is rendered server-side by Ui::HabitChain; this controller does
// not change the DOM beyond toggling state classes.
export default class extends Controller {
  static values = {
    step: { type: Number, default: 35 },
    pulseToday: { type: Boolean, default: true }
  }

  connect() {
    this.links = Array.from(this.element.querySelectorAll(".chain-link"))
    if (this.prefersReducedMotion()) {
      this.links.forEach((link) => link.classList.add("chain-link--enter"))
      this.markPulse()
      return
    }
    this.observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting && !this.started) {
          this.started = true
          this.animate()
          this.observer.disconnect()
        }
      })
    }, { threshold: 0.1, rootMargin: "0px 0px -10% 0px" })
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  animate() {
    this.links.forEach((link, idx) => {
      setTimeout(() => link.classList.add("chain-link--enter"), idx * this.stepValue)
    })
    setTimeout(() => this.markPulse(), this.links.length * this.stepValue)
  }

  markPulse() {
    if (!this.pulseTodayValue) return
    const pending = this.element.querySelector(".chain-link--today_pending")
    pending?.classList.add("chain-link--pulse")
  }

  prefersReducedMotion() {
    return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
  }
}
