import { Controller } from "@hotwired/stimulus"

// Tiny, axis-less ECharts line/area or bar sparkline. Designed to sit at the
// bottom of a stat card and add 7-day context to a single number — no labels,
// no tooltip, no legend. Animates in on first paint.
//
// Usage:
//   <div data-controller="sparkline"
//        data-sparkline-data-value='[1,3,2,5,4,6,8]'
//        data-sparkline-color-value="#6B8E5A"
//        data-sparkline-type-value="area"
//        class="h-8"></div>
export default class extends Controller {
  static values = {
    data: Array,
    color: { type: String, default: "#B8860B" },
    type: { type: String, default: "area" }, // area | line | bar
    height: { type: Number, default: 0 } // 0 = use element's CSS height
  }

  connect() {
    if (!window.echarts) return
    this.chart = window.echarts.init(this.element, null, { renderer: "canvas" })
    this.resizeObserver = new ResizeObserver(() => this.chart && this.chart.resize())
    this.resizeObserver.observe(this.element)
    this.render()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.chart?.dispose()
    this.chart = null
  }

  render() {
    const data = this.dataValue
    if (!data || data.length === 0) return

    const isBar = this.typeValue === "bar"
    const isArea = this.typeValue === "area"

    const series = {
      type: isBar ? "bar" : "line",
      data,
      smooth: !isBar,
      symbol: "none",
      lineStyle: isBar ? undefined : { color: this.colorValue, width: 2 },
      itemStyle: isBar
        ? {
            color: this.colorValue,
            borderRadius: [2, 2, 0, 0]
          }
        : { color: this.colorValue },
      areaStyle: isArea
        ? {
            color: {
              type: "linear", x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: this.withAlpha(this.colorValue, 0.45) },
                { offset: 1, color: this.withAlpha(this.colorValue, 0.02) }
              ]
            }
          }
        : undefined,
      animationDuration: 700,
      animationEasing: "cubicOut"
    }

    this.chart.setOption({
      backgroundColor: "transparent",
      grid: { left: 0, right: 0, top: 2, bottom: 0, containLabel: false },
      xAxis: { type: "category", show: false, boundaryGap: isBar },
      yAxis: { type: "value", show: false, min: (v) => Math.min(v.min, 0) },
      tooltip: { show: false },
      series: [series]
    }, true)
  }

  withAlpha(hex, alpha) {
    if (!hex || !hex.startsWith("#")) return hex
    const num = parseInt(hex.slice(1), 16)
    const r = (num >> 16) & 0xff
    const g = (num >> 8) & 0xff
    const b = num & 0xff
    return `rgba(${r}, ${g}, ${b}, ${alpha})`
  }
}
