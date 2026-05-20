import { Controller } from "@hotwired/stimulus"

// Pomodoro-style timer. Counts down, persists a FocusSession on start,
// marks it completed when the timer finishes.
export default class extends Controller {
  static targets = ["display", "startBtn", "stopBtn"]
  static values  = { durationMinutes: { type: Number, default: 25 }, todoId: String }

  connect() {
    this.remaining = this.durationMinutesValue * 60
    this.render()
  }

  async start() {
    if (this.timer) return
    const res = await fetch("/focus_sessions", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken() },
      body: JSON.stringify({ duration_minutes: this.durationMinutesValue, todo_id: this.todoIdValue, mode: "focus" })
    })
    const data = await res.json()
    this.sessionId = data.id
    this.tick()
  }

  stop() {
    if (this.timer) { clearInterval(this.timer); this.timer = null }
    this.remaining = this.durationMinutesValue * 60
    this.render()
  }

  tick() {
    this.timer = setInterval(() => {
      this.remaining -= 1
      if (this.remaining <= 0) {
        clearInterval(this.timer); this.timer = null
        this.complete()
      }
      this.render()
    }, 1000)
  }

  async complete() {
    if (!this.sessionId) return
    await fetch(`/focus_sessions/${this.sessionId}`, {
      method: "PATCH",
      headers: { "X-CSRF-Token": this.csrfToken() }
    })
    if ("Notification" in window && Notification.permission === "granted") {
      new Notification("Meridian", { body: "Focus session done — take a break." })
    }
  }

  render() {
    const m = Math.floor(this.remaining / 60).toString().padStart(2, "0")
    const s = (this.remaining % 60).toString().padStart(2, "0")
    if (this.hasDisplayTarget) this.displayTarget.textContent = `${m}:${s}`
  }

  csrfToken() { return document.querySelector('meta[name="csrf-token"]')?.content || "" }
}
