import { Controller } from "@hotwired/stimulus"

// Makes the today link in a habit chain SVG behave like a button: a click (or
// Enter / Space keypress when focused) posts to the habit's toggle_today URL
// via a hidden form so Turbo intercepts and the existing turbo_stream response
// replaces the row, the perfect-day widget, and the today-progress card.
// Only attached to the today_pending/completed last link via Ui::HabitChain's
// interactive_today: option.
export default class extends Controller {
  static values = { url: String }

  submit(event) {
    if (event.type === "keyup" && !["Enter", " ", "Space"].includes(event.key)) return
    event.preventDefault()

    const form = document.createElement("form")
    form.method = "post"
    form.action = this.urlValue
    form.style.display = "none"

    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    const methodField = document.createElement("input")
    methodField.type = "hidden"
    methodField.name = "_method"
    methodField.value = "patch"
    form.appendChild(methodField)

    if (csrf) {
      const tokenField = document.createElement("input")
      tokenField.type = "hidden"
      tokenField.name = "authenticity_token"
      tokenField.value = csrf
      form.appendChild(tokenField)
    }

    document.body.appendChild(form)
    form.requestSubmit ? form.requestSubmit() : form.submit()
    setTimeout(() => form.remove(), 0)
  }
}
