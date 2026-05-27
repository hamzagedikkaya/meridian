import { Controller } from "@hotwired/stimulus"

// Adds two layered behaviours to a habit row:
// 1. Tap-pop animation on the toggle button (instant tactile feedback before
//    the turbo-frame swaps it).
// 2. Confetti burst when today's toggle bumps the current_streak across a
//    milestone (7 / 14 / 30 / 100 / 365 days). Uses localStorage to track the
//    previously-seen streak per habit so the celebration only fires once per
//    actual transition — not on every page load.
const MILESTONES = [7, 14, 30, 100, 365]
const STORAGE_PREFIX = "meridian:habit:"

export default class extends Controller {
  static targets = ["button"]
  static values = {
    habitId: String,
    streak: Number
  }

  connect() {
    this.celebrateIfMilestone()
    this.persistStreak()
  }

  pop() {
    if (!this.hasButtonTarget) return
    this.buttonTarget.classList.remove("tap-pop")
    // Force reflow so the animation restarts even on rapid re-clicks.
    void this.buttonTarget.offsetWidth
    this.buttonTarget.classList.add("tap-pop")
  }

  celebrateIfMilestone() {
    if (!window.confetti) return
    if (!MILESTONES.includes(this.streakValue)) return

    const key = STORAGE_PREFIX + this.habitIdValue + ":streak"
    const stored = window.localStorage.getItem(key)
    // First time seeing this habit — store baseline without celebrating, so
    // visiting the page doesn't congratulate a streak that was already there.
    if (stored === null) return

    const last = parseInt(stored, 10)
    if (this.streakValue > last) this.fireConfetti()
  }

  persistStreak() {
    const key = STORAGE_PREFIX + this.habitIdValue + ":streak"
    window.localStorage.setItem(key, this.streakValue.toString())
  }

  fireConfetti() {
    const colors = ["#B8860B", "#D4A574", "#E8C170", "#FDE7A8", "#6B8E5A"]
    const rect = this.element.getBoundingClientRect()
    const x = (rect.left + rect.width / 2) / window.innerWidth
    const y = (rect.top + rect.height / 2) / window.innerHeight
    window.confetti({
      particleCount: 90,
      spread: 70,
      startVelocity: 35,
      origin: { x, y },
      colors,
      ticks: 220,
      scalar: 0.9
    })
  }
}
