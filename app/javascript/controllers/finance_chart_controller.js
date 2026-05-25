import { Controller } from "@hotwired/stimulus"

// Drives the finance dashboard's main chart card: toggles between a category
// pie chart (1m / 6m / 1y ranges) and the existing income-vs-expense trend.
// Data for every range and the trend is pre-serialized in data-values so we
// can swap charts without a round-trip to the server.
export default class extends Controller {
  static targets = ["chart", "rangeButton", "viewButton", "rangeControls", "emptyState"]
  static values = {
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
    currentRange: { type: String, default: "m1" },
    currentView: { type: String, default: "pie" }
  }

  connect() {
    this.chart = null
    this.registerDataLabels()
    this.refresh()
  }

  registerDataLabels() {
    if (!window.ChartDataLabels || !window.Chart) return
    if (!window.Chart.registry.plugins.get("datalabels")) {
      window.Chart.register(window.ChartDataLabels)
      // Default OFF for every chart in the app — opt in explicitly where needed.
      window.Chart.defaults.set("plugins.datalabels", { display: false })
    }
  }

  formatMoney(value) {
    const formatted = value.toLocaleString(this.localeValue || "tr", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })
    return this.currencySymbolValue ? `${formatted} ${this.currencySymbolValue}` : formatted
  }

  disconnect() {
    this.destroyChart()
  }

  setRange(event) {
    const range = event.currentTarget.dataset.range
    if (!range || range === this.currentRangeValue) return
    this.currentRangeValue = range
    this.refresh()
  }

  setView(event) {
    const view = event.currentTarget.dataset.view
    if (!view || view === this.currentViewValue) return
    this.currentViewValue = view
    this.refresh()
  }

  refresh() {
    this.destroyChart()
    this.syncButtonStyles()
    this.toggleRangeControls()
    if (this.currentViewValue === "pie") {
      this.renderPie()
    } else {
      this.renderTrend()
    }
  }

  destroyChart() {
    if (this.chart && typeof this.chart.destroy === "function") this.chart.destroy()
    this.chart = null
    if (this.hasChartTarget) this.chartTarget.innerHTML = ""
  }

  renderPie() {
    const dataset = this.currentPieDataset()
    if (!dataset || dataset.length === 0) {
      this.showEmptyState()
      return
    }
    this.hideEmptyState()

    const data = dataset.map(d => [d.name, Number((d.amount / 100).toFixed(2))])
    const colors = dataset.map(d => d.color)

    const format = (v) => this.formatMoney(v)
    this.chart = new Chartkick.PieChart(this.chartTarget, data, {
      colors: colors,
      height: "240px",
      library: {
        plugins: {
          legend: {
            position: "bottom",
            labels: { color: "#A09B8E", padding: 12, boxWidth: 12 }
          },
          tooltip: {
            callbacks: {
              label: (ctx) => {
                const total = ctx.dataset.data.reduce((a, b) => a + b, 0)
                const pct = total > 0 ? ((ctx.parsed / total) * 100).toFixed(1) : 0
                return `${ctx.label}: ${format(ctx.parsed)} (${pct}%)`
              }
            }
          },
          datalabels: {
            display: "auto",
            color: "#FFFFFF",
            font: { size: 10, weight: "500" },
            textAlign: "center",
            anchor: "center",
            align: "center",
            formatter: (value, ctx) => {
              const total = ctx.dataset.data.reduce((a, b) => a + b, 0)
              if (total === 0) return ""
              const pct = (value / total) * 100
              if (pct < 5) return ""
              const name = ctx.chart.data.labels[ctx.dataIndex] || ""
              return [ name, `${pct.toFixed(0)}%` ]
            }
          }
        }
      }
    })
  }

  renderTrend() {
    this.hideEmptyState()
    const format = (v) => this.formatMoney(v)
    this.chart = new Chartkick.ColumnChart(this.chartTarget, [
      { name: this.incomeLabelValue, data: this.trendIncomeValue },
      { name: this.expenseLabelValue, data: this.trendExpenseValue }
    ], {
      colors: [this.incomeColorValue, this.expenseColorValue],
      height: "240px",
      library: {
        plugins: {
          legend: { labels: { color: "#A09B8E" } },
          tooltip: {
            callbacks: {
              label: (ctx) => `${ctx.dataset.label}: ${format(ctx.parsed.y)}`
            }
          },
          datalabels: { display: false }
        },
        scales: {
          x: { ticks: { color: "#A09B8E" }, grid: { display: false } },
          y: { ticks: { color: "#A09B8E" }, grid: { color: "rgba(245,241,232,0.06)" } }
        }
      }
    })
  }

  currentPieDataset() {
    switch (this.currentRangeValue) {
      case "m6": return this.pieM6Value
      case "y1": return this.pieY1Value
      default:   return this.pieM1Value
    }
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
