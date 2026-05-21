import { Controller } from "@hotwired/stimulus"

// Weekly calendar with hour-grid and vertical drag for time adjustment.
// Drop position (Y pixel) → time-of-day, drop column → day.
// Slots snap to 15-minute increments.
export default class extends Controller {
  static targets = ["dayColumn"]
  static values = {
    hourHeight: { type: Number, default: 48 },
    dayStart:   { type: Number, default: 6 }, // first hour shown in the grid
    snap:       { type: Number, default: 15 } // snap minutes
  }

  eventDragStart(event) {
    const tile = event.currentTarget
    const id = tile.dataset.eventId
    const duration = parseInt(tile.dataset.durationMinutes || "60", 10)

    event.dataTransfer.setData("text/plain", JSON.stringify({ id, duration }))
    event.dataTransfer.effectAllowed = "move"

    // Capture offset within the tile so the drop position represents the *start* of the event
    const rect = tile.getBoundingClientRect()
    this.dragOffsetY = event.clientY - rect.top
    tile.classList.add("opacity-50")
  }

  eventDragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
  }

  dayDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  async dayDrop(event) {
    event.preventDefault()
    const column = event.currentTarget
    const rect = column.getBoundingClientRect()
    const y = event.clientY - rect.top - (this.dragOffsetY || 0)

    let payload
    try {
      payload = JSON.parse(event.dataTransfer.getData("text/plain"))
    } catch (e) {
      return
    }
    const { id, duration } = payload
    if (!id) return

    // Convert pixel offset to minutes since dayStart hour, snap to nearest snap interval
    const minutesFromStart = Math.max(0, Math.round(y / this.hourHeightValue * 60))
    const snapped = Math.round(minutesFromStart / this.snapValue) * this.snapValue
    const startMinutes = this.dayStartValue * 60 + snapped
    const startH = Math.floor(startMinutes / 60)
    const startM = startMinutes % 60

    const date = column.dataset.date
    const start_at = `${date}T${String(startH).padStart(2, "0")}:${String(startM).padStart(2, "0")}`

    const endMinutes = startMinutes + duration
    const endH = Math.floor(endMinutes / 60)
    const endM = endMinutes % 60
    const end_at = `${date}T${String(endH).padStart(2, "0")}:${String(endM).padStart(2, "0")}`

    const res = await fetch(`/events/${id}/reschedule`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ start_at, end_at })
    })

    if (res.ok) {
      window.location.reload()
    } else {
      console.warn("Reschedule failed", res.status)
    }
  }

  openEvent(event) {
    // Don't open during a drag
    if (event.defaultPrevented) return
    const id = event.currentTarget.dataset.eventId
    if (!id) return
    // Navigate to edit URL with turbo-frame modal
    const link = document.createElement("a")
    link.href = `/events/${id}/edit`
    link.dataset.turboFrame = "modal"
    document.body.appendChild(link)
    link.click()
    link.remove()
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
