import { Controller } from "@hotwired/stimulus"

// Finance dashboard chart card — driven by Apache ECharts for the richer motion
// (radial gradients per slice, segment-explode on hover, smooth scale-in entrance,
// elastic transitions between ranges, animated bar entrance on the trend view).
// Chart.js + Chartkick are still loaded for simpler widgets elsewhere in the app.
export default class extends Controller {
  static targets = ["chart", "rangeButton", "viewButton", "rangeControls", "emptyState", "totalLabel", "customFrom", "customTo", "account"]
  static values = {
    pieD1: Array,
    pieW1: Array,
    pieM1: Array,
    pieM6: Array,
    pieY1: Array,
    trendIncome: Object,
    trendExpense: Object,
    incomeLabel: String,
    expenseLabel: String,
    incomeColor: { type: String, default: "#6B8E5A" },
    expenseColor: { type: String, default: "#B85450" },
    currencySymbol: { type: String, default: "" },
    locale: { type: String, default: "tr" },
    directLabel: { type: String, default: "" },
    totalCaption: { type: String, default: "" },
    rangeStarts: { type: Object, default: {} },
    transactionsUrl: { type: String, default: "" },
    pieUrl: { type: String, default: "" },
    currentRange: { type: String, default: "m1" },
    currentView: { type: String, default: "pie" }
  }

  connect() {
    if (!window.echarts) return
    this.chart = window.echarts.init(this.chartTarget, null, { renderer: "canvas" })
    this.resizeObserver = new ResizeObserver(() => this.chart && this.chart.resize())
    this.resizeObserver.observe(this.chartTarget)
    this.chart.on("click", (params) => this.handlePieClick(params))
    this.syncCustomInputsToCurrentRange()
    this.refresh()
  }

  syncCustomInputsToCurrentRange() {
    if (this.currentRangeValue === "custom") return
    const starts = this.rangeStartsValue || {}
    if (this.hasCustomFromTarget) this.customFromTarget.value = starts[this.currentRangeValue] || ""
    if (this.hasCustomToTarget)   this.customToTarget.value   = starts.today || ""
  }

  handlePieClick(params) {
    if (this.currentViewValue !== "pie") return
    const id = params?.data?.id
    if (!id || !this.transactionsUrlValue) return
    const url = new URL(this.transactionsUrlValue, window.location.origin)
    url.searchParams.set("category_id", id)
    const { from, to } = this.activeRangeBounds()
    if (from) url.searchParams.set("from", from)
    if (to) url.searchParams.set("to", to)
    const acc = this.accountId()
    if (acc) url.searchParams.set("account_id", acc)
    window.location.href = url.toString()
  }

  accountId() {
    return this.hasAccountTarget ? this.accountTarget.value : ""
  }

  activeRangeBounds() {
    if (this.currentRangeValue === "custom") {
      return { from: this.hasCustomFromTarget ? this.customFromTarget.value : null,
               to:   this.hasCustomToTarget   ? this.customToTarget.value   : null }
    }
    const starts = this.rangeStartsValue || {}
    return { from: starts[this.currentRangeValue], to: starts.today }
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.chart?.dispose()
    this.chart = null
  }

  setRange(event) {
    const range = event.currentTarget.dataset.range
    if (!range || range === this.currentRangeValue) return
    // Mirror the preset's window into the custom-range inputs so the user
    // can see exactly which dates the active button represents and tweak
    // either end without restarting from blanks. Assigning .value directly
    // does NOT fire a `change` event, so this won't loop into customRangeChanged.
    const starts = this.rangeStartsValue || {}
    if (this.hasCustomFromTarget) this.customFromTarget.value = starts[range] || ""
    if (this.hasCustomToTarget)   this.customToTarget.value   = starts.today || ""
    this.currentRangeValue = range
    if (this.accountId()) {
      // Preset windows are baked in for ALL accounts only — when an account is
      // selected we must fetch that preset's window scoped to the account.
      this.fetchPie(starts[range], starts.today)
    } else {
      this.fetchedDataset = null
      this.refresh()
    }
  }

  customRangeChanged() {
    const from = this.hasCustomFromTarget ? this.customFromTarget.value : ""
    const to   = this.hasCustomToTarget   ? this.customToTarget.value   : ""
    if (!from || !to) return
    if (from > to) return
    this.currentRangeValue = "custom"
    this.fetchPie(from, to)
  }

  // Re-resolve the current range under the (possibly changed) account filter.
  accountChanged() {
    const { from, to } = this.activeRangeBounds()
    if (this.accountId() || this.currentRangeValue === "custom") {
      this.fetchPie(from, to)
    } else {
      this.fetchedDataset = null
      this.refresh()
    }
  }

  // Fetch a category-pie dataset from the server for [from, to], scoped to the
  // selected account when one is chosen. Used for custom ranges and for ANY
  // range once an account filter is active.
  async fetchPie(from, to) {
    if (!this.pieUrlValue || !from || !to) return
    const url = new URL(this.pieUrlValue, window.location.origin)
    url.searchParams.set("from", from)
    url.searchParams.set("to", to)
    const acc = this.accountId()
    if (acc) url.searchParams.set("account_id", acc)
    try {
      const res = await fetch(url.toString(), { headers: { Accept: "application/json" } })
      if (!res.ok) return
      const json = await res.json()
      this.fetchedDataset = json.pie || []
      this.refresh()
    } catch (_e) {
      // network errors fall through silently — the user can retry
    }
  }

  setView(event) {
    const view = event.currentTarget.dataset.view
    if (!view || view === this.currentViewValue) return
    this.currentViewValue = view
    this.refresh()
  }

  refresh() {
    if (!this.chart) return
    this.syncButtonStyles()
    this.toggleRangeControls()
    if (this.currentViewValue === "pie") {
      this.renderPie()
    } else {
      this.renderTrend()
    }
  }

  renderPie() {
    const dataset = this.currentPieDataset()
    if (!dataset || dataset.length === 0) {
      this.chart.clear()
      this.showEmptyState()
      this.updateTotal(0)
      return
    }
    this.hideEmptyState()
    this.chart.setOption(this.pieOption(dataset), true)
    const totalCents = dataset.reduce((sum, d) => sum + Number(d.amount || 0), 0)
    this.updateTotal(totalCents / 100)
  }

  renderTrend() {
    this.hideEmptyState()
    this.chart.setOption(this.trendOption(), true)
    this.updateTotal(null) // total label only makes sense on the pie view
  }

  updateTotal(amount) {
    if (!this.hasTotalLabelTarget) return
    if (amount === null) {
      this.totalLabelTarget.textContent = ""
      return
    }
    const caption = this.totalCaptionValue || ""
    this.totalLabelTarget.textContent = caption ? `${caption}: ${this.formatMoney(amount)}` : this.formatMoney(amount)
  }

  pieOption(dataset) {
    const format = (v) => this.formatMoney(v)
    const directLabel = this.directLabelValue
    return {
      backgroundColor: "transparent",
      tooltip: {
        trigger: "item",
        backgroundColor: "rgba(20,18,15,0.95)",
        borderColor: "rgba(245,241,232,0.1)",
        textStyle: { color: "#F5F1E8" },
        formatter: (p) => {
          const header = `<div style="font-weight:600;margin-bottom:3px">${p.name}</div>`
          const totalLine = `<div style="margin-bottom:6px">${format(p.value)} <span style="opacity:.6">(${p.percent.toFixed(1)}%)</span></div>`
          const breakdown = p.data.breakdown || []
          if (breakdown.length === 0) return header + totalLine
          const rows = breakdown.map(b => {
            const label = b.is_root ? `${b.name} ${directLabel}` : b.name
            return `<div style="display:flex;justify-content:space-between;gap:14px;font-size:12px;opacity:.85"><span>${label}</span><span>${format(b.amount / 100)}</span></div>`
          }).join("")
          return header + totalLine + `<div style="border-top:1px solid rgba(245,241,232,0.12);padding-top:5px;margin-top:1px">${rows}</div>`
        }
      },
      legend: {
        orient: "horizontal",
        bottom: 6,
        itemWidth: 12,
        itemHeight: 12,
        textStyle: { color: "#A09B8E", fontSize: 11 },
        icon: "circle"
      },
      series: [{
        type: "pie",
        radius: ["0%", "75%"],
        center: ["50%", "44%"],
        avoidLabelOverlap: true,
        itemStyle: {
          borderRadius: 4,
          borderColor: "rgba(20,18,15,0.45)",
          borderWidth: 2
        },
        label: {
          show: true,
          position: "inside",
          color: "#FFFFFF",
          fontSize: 11,
          fontWeight: 500,
          textShadowColor: "rgba(0,0,0,0.45)",
          textShadowBlur: 3,
          formatter: (p) => p.percent < 5 ? "" : `{n|${p.name}}\n{p|${p.percent.toFixed(0)}%}`,
          rich: {
            n: { fontSize: 11, fontWeight: 600, color: "#FFFFFF", lineHeight: 14 },
            p: { fontSize: 10, color: "#FFFFFF", opacity: 0.85, lineHeight: 12 }
          }
        },
        labelLine: { show: false },
        emphasis: {
          scale: true,
          scaleSize: 10,
          itemStyle: {
            shadowBlur: 18,
            shadowColor: "rgba(184, 134, 11, 0.35)"
          },
          label: { show: true, fontSize: 12, fontWeight: 700 }
        },
        data: dataset.map((d, idx) => ({
          name: d.name,
          id: d.id,
          value: Number((d.amount / 100).toFixed(2)),
          breakdown: d.breakdown || [],
          itemStyle: {
            color: {
              type: "radial",
              x: 0.5, y: 0.5, r: 0.85,
              colorStops: [
                { offset: 0, color: this.lighten(d.color, 0.22) },
                { offset: 1, color: d.color }
              ]
            }
          }
        })),
        animationType: "scale",
        animationDuration: 800,
        animationEasing: "elasticOut",
        animationDelay: (idx) => idx * 60,
        animationDurationUpdate: 600,
        animationEasingUpdate: "cubicOut"
      }]
    }
  }

  trendOption() {
    const labels = Object.keys(this.trendIncomeValue)
    const format = (v) => this.formatMoney(v)
    return {
      backgroundColor: "transparent",
      tooltip: {
        trigger: "axis",
        backgroundColor: "rgba(20,18,15,0.95)",
        borderColor: "rgba(245,241,232,0.1)",
        textStyle: { color: "#F5F1E8" },
        axisPointer: { type: "shadow", shadowStyle: { color: "rgba(245,241,232,0.04)" } },
        formatter: (params) => {
          const header = `<div style="font-weight:500;margin-bottom:4px">${params[0].axisValue}</div>`
          const rows = params.map(p => `${p.marker}${p.seriesName}: <b>${format(p.value)}</b>`).join("<br/>")
          return header + rows
        }
      },
      legend: {
        bottom: 6,
        textStyle: { color: "#A09B8E", fontSize: 11 },
        icon: "circle",
        itemWidth: 12,
        itemHeight: 12
      },
      grid: { left: 50, right: 16, top: 14, bottom: 44 },
      xAxis: {
        type: "category",
        data: labels,
        axisLine: { lineStyle: { color: "rgba(245,241,232,0.12)" } },
        axisTick: { show: false },
        axisLabel: { color: "#A09B8E", fontSize: 11 }
      },
      yAxis: {
        type: "value",
        axisLabel: { color: "#A09B8E", fontSize: 10, formatter: (v) => this.compactNumber(v) },
        splitLine: { lineStyle: { color: "rgba(245,241,232,0.06)" } }
      },
      series: [
        {
          name: this.incomeLabelValue,
          type: "bar",
          data: labels.map(l => this.trendIncomeValue[l]),
          itemStyle: {
            borderRadius: [6, 6, 0, 0],
            color: { type: "linear", x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: this.lighten(this.incomeColorValue, 0.18) },
                { offset: 1, color: this.incomeColorValue }
              ] }
          },
          emphasis: { itemStyle: { shadowBlur: 12, shadowColor: "rgba(107,142,90,0.45)" } },
          animationDelay: (idx) => idx * 70
        },
        {
          name: this.expenseLabelValue,
          type: "bar",
          data: labels.map(l => this.trendExpenseValue[l]),
          itemStyle: {
            borderRadius: [6, 6, 0, 0],
            color: { type: "linear", x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: this.lighten(this.expenseColorValue, 0.18) },
                { offset: 1, color: this.expenseColorValue }
              ] }
          },
          emphasis: { itemStyle: { shadowBlur: 12, shadowColor: "rgba(184,84,80,0.45)" } },
          animationDelay: (idx) => idx * 70 + 35
        }
      ],
      animationDuration: 700,
      animationEasing: "cubicOut",
      animationDurationUpdate: 500
    }
  }

  currentPieDataset() {
    if (this.usesFetchedData()) return this.fetchedDataset || []
    switch (this.currentRangeValue) {
      case "d1": return this.pieD1Value
      case "w1": return this.pieW1Value
      case "m6": return this.pieM6Value
      case "y1": return this.pieY1Value
      default:   return this.pieM1Value
    }
  }

  // Data comes from the server (not the baked presets) for custom ranges and
  // whenever an account filter is active.
  usesFetchedData() {
    return this.currentRangeValue === "custom" || this.accountId() !== ""
  }

  formatMoney(value) {
    const formatted = Number(value).toLocaleString(this.localeValue || "tr", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })
    return this.currencySymbolValue ? `${formatted} ${this.currencySymbolValue}` : formatted
  }

  compactNumber(value) {
    const abs = Math.abs(value)
    if (abs >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`
    if (abs >= 1_000)     return `${(value / 1_000).toFixed(1)}k`
    return value.toString()
  }

  lighten(hex, amt) {
    if (!hex || !hex.startsWith("#")) return hex
    const num = parseInt(hex.slice(1), 16)
    const r = Math.min(255, (num >> 16) + Math.round(255 * amt))
    const g = Math.min(255, ((num >> 8) & 0xff) + Math.round(255 * amt))
    const b = Math.min(255, (num & 0xff) + Math.round(255 * amt))
    return `rgb(${r}, ${g}, ${b})`
  }

  showEmptyState() {
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.remove("hidden")
  }
  hideEmptyState() {
    if (this.hasEmptyStateTarget) this.emptyStateTarget.classList.add("hidden")
  }

  syncButtonStyles() {
    this.rangeButtonTargets.forEach(btn => {
      const active = btn.dataset.range === this.currentRangeValue
      btn.classList.toggle("bg-[var(--color-bg-overlay)]", active)
      btn.classList.toggle("text-[var(--color-fg-primary)]", active)
      btn.classList.toggle("text-[var(--color-fg-muted)]", !active)
    })
    this.viewButtonTargets.forEach(btn => {
      const active = btn.dataset.view === this.currentViewValue
      btn.classList.toggle("bg-[var(--color-bg-overlay)]", active)
      btn.classList.toggle("text-[var(--color-fg-primary)]", active)
      btn.classList.toggle("text-[var(--color-fg-muted)]", !active)
    })
  }

  toggleRangeControls() {
    if (!this.hasRangeControlsTarget) return
    this.rangeControlsTarget.classList.toggle("invisible", this.currentViewValue !== "pie")
  }
}
