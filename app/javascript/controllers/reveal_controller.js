import { Controller } from "@hotwired/stimulus"

// Toggles visibility of a content panel and swaps the trigger label.
// Usage:
//   <div data-controller="reveal">
//     <button data-action="reveal#toggle">
//       <span data-reveal-target="showLabel">Show</span>
//       <span data-reveal-target="hideLabel" class="hidden">Hide</span>
//     </button>
//     <div data-reveal-target="content" class="hidden">...</div>
//   </div>
export default class extends Controller {
  static targets = ["content", "showLabel", "hideLabel"]

  toggle(event) {
    event.preventDefault()
    this.contentTarget.classList.toggle("hidden")

    if (this.hasShowLabelTarget && this.hasHideLabelTarget) {
      this.showLabelTarget.classList.toggle("hidden")
      this.hideLabelTarget.classList.toggle("hidden")
    }
  }
}
