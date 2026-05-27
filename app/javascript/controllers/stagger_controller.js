import { Controller } from "@hotwired/stimulus"

// Marks direct children with [data-stagger-child] and assigns each one a
// --stagger-index custom property so the CSS `card-enter` animation fires
// with a per-item delay. Drop on any container:
//   <div data-controller="stagger" class="grid ..."> <div class="card">…</div> … </div>
//
// Optional: pass a selector via data-stagger-selector-value to target nested
// elements (e.g. ".card") instead of direct children.
export default class extends Controller {
  static values = {
    selector: { type: String, default: "" },
    step: { type: Number, default: 60 }
  }

  connect() {
    const children = this.selectorValue
      ? this.element.querySelectorAll(this.selectorValue)
      : this.element.children

    Array.from(children).forEach((child, index) => {
      child.setAttribute("data-stagger-child", "")
      child.style.setProperty("--stagger-index", index.toString())
    })
  }
}
