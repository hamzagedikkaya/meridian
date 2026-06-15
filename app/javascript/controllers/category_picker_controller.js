import { Controller } from "@hotwired/stimulus"

// Custom finance-category dropdown — replaces the native <select> so the
// panel can render color dots, indented subcategories, and expand/collapse
// each parent. The hidden <input> carries the selected id for form submit.
//
// A search box (shown for long lists) filters roots AND subcategories as you
// type: matching subcategories surface with their parent for context, and the
// group auto-expands so the match is visible. Matching is Turkish-aware and
// diacritic-insensitive, so "te" finds "Temel ihtiyaç" and "icecek" finds
// "İçecek".
//
// The transaction-form controller talks to this picker through a Stimulus
// value (`data-category-picker-kind-value`): writing the attribute triggers
// `kindValueChanged()`, which filters the panel. Going through a value
// (not a method call) avoids the controller-bootstrap race where the
// outer form connects before the inner picker is registered.
export default class extends Controller {
  static targets = ["trigger", "panel", "display", "hidden", "group", "children", "chevron", "search", "empty"]
  static values = {
    blankLabel: { type: String, default: "" },
    kind: { type: String, default: "" }
  }

  static SELECT = "button[data-action*='category-picker#select']"

  initialize() {
    this.query = ""
  }

  connect() {
    this.documentClick = (e) => { if (!this.element.contains(e.target)) this.close() }
    this.escHandler = (e) => { if (e.key === "Escape" && !this.panelTarget.classList.contains("hidden")) this.close() }
    document.addEventListener("click", this.documentClick)
    document.addEventListener("keydown", this.escHandler)
    this.refreshHighlights()
    this.openGroupContainingSelection()
  }

  disconnect() {
    document.removeEventListener("click", this.documentClick)
    document.removeEventListener("keydown", this.escHandler)
  }

  // Called by Stimulus when the kind value attribute changes (including the
  // initial read on connect). Empty kind = no filter (subscription/account forms).
  kindValueChanged() {
    this.applyFilters()
    this.enforceKindSelection()
  }

  toggle(event) {
    event.preventDefault()
    // No stopPropagation — let the click bubble so sibling pickers close via
    // their own document listener. Our listener guards with element.contains
    // so this picker won't self-close.
    const willOpen = this.panelTarget.classList.contains("hidden")
    this.panelTarget.classList.toggle("hidden", !willOpen)
    if (willOpen) this.onOpen()
  }

  onOpen() {
    this.query = ""
    if (this.hasSearchTarget) {
      this.searchTarget.value = ""
      this.applyFilters()
      this.searchTarget.focus()
    } else {
      this.applyFilters()
    }
  }

  close() {
    this.panelTarget.classList.add("hidden")
  }

  select(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    this.applySelection(btn.dataset.id || "", btn.dataset.name || "", btn.dataset.color || "")
    this.close()
  }

  toggleGroup(event) {
    event.preventDefault()
    event.stopPropagation()
    const chevron = event.currentTarget
    const group = chevron.closest("[data-category-picker-target='group']")
    const children = group.querySelector("[data-category-picker-target='children']")
    if (!children) return
    this.setExpanded(group, children.classList.contains("hidden"))
  }

  // --- Search ---------------------------------------------------------------

  search(event) {
    this.query = event.target.value
    this.applyFilters()
  }

  searchKeydown(event) {
    if (event.key !== "Enter") return
    // Don't submit the surrounding form; pick the first visible match instead.
    event.preventDefault()
    const first = this.firstVisibleOption()
    if (first) first.click()
  }

  applyFilters() {
    const q = this.normalize(this.query)
    if (!q) { this.showAllRespectingKind(); return }

    let anyVisible = false
    this.groupTargets.forEach(group => {
      if (!this.kindMatches(group)) { group.hidden = true; return }

      const rootMatch = this.normalize(this.rootName(group)).includes(q)
      const children = this.childrenContainer(group)
      let childMatch = false
      if (children) {
        children.querySelectorAll(this.constructor.SELECT).forEach(btn => {
          const match = this.normalize(btn.dataset.name || "").includes(q)
          btn.hidden = !(match || rootMatch)
          if (match) childMatch = true
        })
        this.setExpanded(group, childMatch)
      }

      const visible = rootMatch || childMatch
      group.hidden = !visible
      if (visible) anyVisible = true
    })

    this.toggleBlankOption(false)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = anyVisible
  }

  showAllRespectingKind() {
    this.groupTargets.forEach(group => {
      group.hidden = !this.kindMatches(group)
      const children = this.childrenContainer(group)
      if (children) {
        children.querySelectorAll(this.constructor.SELECT).forEach(btn => { btn.hidden = false })
        this.setExpanded(group, false)
      }
    })
    this.toggleBlankOption(true)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
    this.openGroupContainingSelection()
  }

  kindMatches(group) {
    return !this.kindValue || group.dataset.kind === this.kindValue
  }

  rootName(group) {
    return group.querySelector(this.constructor.SELECT)?.dataset.name || ""
  }

  childrenContainer(group) {
    return group.querySelector("[data-category-picker-target='children']")
  }

  setExpanded(group, expanded) {
    const children = this.childrenContainer(group)
    if (!children) return
    children.classList.toggle("hidden", !expanded)
    const chevron = group.querySelector("[data-category-picker-target='chevron']")
    chevron?.setAttribute("aria-expanded", expanded ? "true" : "false")
    chevron?.querySelector("svg")?.classList.toggle("rotate-180", expanded)
  }

  toggleBlankOption(show) {
    const blank = this.element.querySelector(`${this.constructor.SELECT}[data-id='']`)
    if (blank) blank.hidden = !show
  }

  firstVisibleOption() {
    return Array.from(this.element.querySelectorAll(this.constructor.SELECT))
      .find(btn => btn.dataset.id && btn.offsetParent !== null)
  }

  // Lowercase (Turkish locale) and fold Turkish diacritics to ASCII so search
  // is forgiving of casing and special characters.
  normalize(value) {
    return (value || "")
      .toLocaleLowerCase("tr")
      .replace(/ı/g, "i").replace(/ş/g, "s").replace(/ğ/g, "g")
      .replace(/ü/g, "u").replace(/ö/g, "o").replace(/ç/g, "c")
      .trim()
  }

  enforceKindSelection() {
    if (!this.kindValue) return
    const current = this.hiddenTarget.value
    if (!current) return
    const stillValid = this.element.querySelector(
      `${this.constructor.SELECT}[data-id='${current}'][data-kind='${this.kindValue}']`
    )
    if (!stillValid) this.applySelection("", "", "")
  }

  applySelection(id, name, color) {
    this.hiddenTarget.value = id
    this.updateDisplay(id, name, color)
    this.refreshHighlights()
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  updateDisplay(id, name, color) {
    this.displayTarget.innerHTML = ""
    if (id && name) {
      const dot = document.createElement("span")
      dot.className = "w-2.5 h-2.5 rounded-full flex-shrink-0 ring-1 ring-inset ring-[rgba(255,255,255,0.15)]"
      dot.style.background = color
      const text = document.createElement("span")
      text.className = "text-sm truncate"
      text.textContent = name
      text.title = name
      this.displayTarget.append(dot, text)
    } else {
      const blank = document.createElement("span")
      blank.className = "text-sm text-[var(--color-fg-muted)]"
      blank.textContent = this.blankLabelValue
      this.displayTarget.append(blank)
    }
  }

  // Panel is derived state from hiddenTarget.value — recompute highlights
  // so a re-pick doesn't leave the old row marked.
  refreshHighlights() {
    const currentId = this.hiddenTarget.value
    this.element.querySelectorAll("[data-action*='category-picker#select']").forEach(btn => {
      if (!btn.dataset.id) return // skip blank-option row
      const isSelected = btn.dataset.id === currentId && currentId !== ""
      const row = btn.closest("[data-picker-row]") || btn
      row.classList.toggle("bg-[var(--color-bg-hover)]", isSelected)
      const label = btn.querySelector("[data-picker-label]")
      label?.classList.toggle("font-medium", isSelected)
      label?.classList.toggle("text-[var(--color-accent-400)]", isSelected)
    })
  }

  // If a child is currently selected, expand its parent group so the user
  // sees the selection without having to click the chevron first.
  openGroupContainingSelection() {
    const id = this.hiddenTarget.value
    if (!id) return
    const selectedBtn = this.element.querySelector(`[data-action*='category-picker#select'][data-id='${id}']`)
    if (!selectedBtn) return
    const childrenContainer = selectedBtn.closest("[data-category-picker-target='children']")
    if (!childrenContainer) return
    const group = childrenContainer.closest("[data-category-picker-target='group']")
    if (group) this.setExpanded(group, true)
  }
}
