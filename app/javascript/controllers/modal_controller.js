import { Controller } from "@hotwired/stimulus"

// Wraps a Turbo Frame so it appears as a centered modal overlay.
//
// DOM shape (declared in the layout):
//   <div data-controller="modal">                 (overlay — fixed inset-0, scrolls)
//     <div data-modal-target="centerer">         (flex min-h-full items-center)
//       <turbo-frame id="modal"></turbo-frame>   (the actual content slot)
//     </div>
//   </div>
//
// The overlay owns the scrollbar; the centerer's `min-h-full` makes it at
// least as tall as the overlay so `items-center` produces real centering
// when content is short, while content taller than the viewport pushes the
// centerer past the overlay's height and scrolls naturally — top stays
// reachable, unlike a single-flex approach where centering can clip.
//
// Esc and click-outside dismiss; Turbo Stream `turbo_stream.update "modal", ""`
// from the server clears it.
const OVERLAY_CLASSES = [
  "fixed", "inset-0", "z-50",
  "bg-black/60", "backdrop-blur-sm",
  "overflow-y-auto"
]

const CENTERER_CLASSES = [
  "flex", "min-h-full", "items-center", "justify-center",
  "py-8", "md:py-12", "px-4"
]

export default class extends Controller {
  static targets = [ "centerer" ]

  connect() {
    this.boundKey = this.handleKey.bind(this)
    this.boundClick = this.handleClick.bind(this)
    this.boundFrameLoad = () => this.refreshOverlay()
    document.addEventListener("keydown", this.boundKey)
    document.addEventListener("turbo:frame-load", this.boundFrameLoad)
    this.refreshOverlay()
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKey)
    document.removeEventListener("turbo:frame-load", this.boundFrameLoad)
    this.hideOverlay()
  }

  refreshOverlay() {
    const frame = this.element.querySelector("turbo-frame#modal")
    if (!frame) return
    if (frame.children.length > 0) {
      this.showOverlay()
    } else {
      this.hideOverlay()
    }
  }

  showOverlay() {
    this.element.classList.remove("hidden")
    this.element.classList.add(...OVERLAY_CLASSES, "modal-overlay-anim")
    if (this.hasCentererTarget) {
      this.centererTarget.classList.add(...CENTERER_CLASSES)
    }
    document.body.style.overflow = "hidden"
    this.element.addEventListener("click", this.boundClick)
  }

  hideOverlay() {
    this.element.classList.add("hidden")
    this.element.classList.remove(...OVERLAY_CLASSES, "modal-overlay-anim")
    if (this.hasCentererTarget) {
      this.centererTarget.classList.remove(...CENTERER_CLASSES)
    }
    document.body.style.overflow = ""
    this.element.removeEventListener("click", this.boundClick)
  }

  handleKey(e) {
    if (e.key === "Escape") this.close()
  }

  handleClick(e) {
    // Click outside the inner modal content — i.e. on the overlay backdrop
    // or on the centerer's empty space (around the content card).
    if (e.target === this.element || e.target === this.centererTarget) {
      this.close()
    }
  }

  close() {
    const frame = this.element.querySelector("turbo-frame#modal")
    if (frame) frame.innerHTML = ""
    this.hideOverlay()
  }
}
