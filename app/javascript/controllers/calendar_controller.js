import { Controller } from "@hotwired/stimulus"

// Monthly calendar drag-and-drop: drag event tiles between day cells to change the
// event's date (preserving time of day).
export default class extends Controller {
  static targets = ["dayCell"]

  // Drag start on event tile
  eventDragStart(event) {
    const link = event.currentTarget
    const id = link.dataset.eventId
    event.dataTransfer.setData("text/plain", id)
    event.dataTransfer.effectAllowed = "move"
    link.classList.add("opacity-50")
    this.draggingId = id
  }

  eventDragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
    this.draggingId = null
    this.dayCellTargets.forEach(c => c.classList.remove("ring-2", "ring-[var(--color-accent-500)]"))
  }

  // Day cell drag over (must preventDefault to allow drop)
  dayDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
    event.currentTarget.classList.add("ring-2", "ring-[var(--color-accent-500)]")
  }

  dayDragLeave(event) {
    event.currentTarget.classList.remove("ring-2", "ring-[var(--color-accent-500)]")
  }

  async dayDrop(event) {
    event.preventDefault()
    const cell = event.currentTarget
    cell.classList.remove("ring-2", "ring-[var(--color-accent-500)]")

    const eventId = event.dataTransfer.getData("text/plain") || this.draggingId
    if (!eventId) return

    const newDate = cell.dataset.date
    const res = await fetch(`/events/${eventId}/move`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ date: newDate })
    })

    if (res.ok) {
      // Reload to reflect the new placement
      window.location.reload()
    } else {
      console.warn("Move failed", res.status)
    }
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
