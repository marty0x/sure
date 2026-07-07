import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import {
  CHART_TOOLTIP_CLASSES,
  CHART_TOOLTIP_CONTEXT_CLASSES,
  CHART_TOOLTIP_VALUE_CLASSES,
} from "utils/chart_tooltip";

// Dedicated controller for the Basis page. Draws a single historical account-
// value line from server-computed points. The tooltip still exposes the stored
// basis legs for attribution, while the line itself uses the server-computed
// combined account-value series for each snapshot (typically spot + Lighter
// account value + funding + rewards when Lighter account value is present).
export default class extends Controller {
  static targets = ["chart"];
  static values = {
    payload: Object,
    labels: Object,
    currency: { type: String, default: "USD" },
    locale: { type: String, default: "en" },
  };

  connect() {
    if (typeof ResizeObserver !== "undefined") {
      this._resizeObserver = new ResizeObserver(() => this._draw());
      this._resizeObserver.observe(this.chartTarget);
    }

    if (typeof MutationObserver !== "undefined") {
      this._themeObserver = new MutationObserver((mutations) => {
        if (mutations.some((m) => m.attributeName === "data-theme")) this._draw();
      });
      this._themeObserver.observe(document.documentElement, { attributes: true });
    }

    this._draw();
  }

  disconnect() {
    this._resizeObserver?.disconnect();
    this._themeObserver?.disconnect();
    this._tooltip?.remove();
  }

  _formatCurrency(value, { compact = false } = {}) {
    try {
      return new Intl.NumberFormat(this.localeValue, {
        style: "currency",
        currency: this.currencyValue,
        ...(compact ? { notation: "compact", maximumFractionDigits: 1 } : {}),
      }).format(value);
    } catch (_e) {
      return `${this.currencyValue} ${value.toFixed(2)}`;
    }
  }

  _draw() {
    const root = this.chartTarget;
    root.innerHTML = "";

    const points = (this.payloadValue.points || []).map((p) => ({
      ...p,
      dateObj: this._parseLocalDate(p.date),
    }));
    if (points.length === 0) return;

    const width = root.clientWidth || 720;
    const height = root.clientHeight || 320;
    if (width <= 0 || height <= 0) return;

    const isDark = document.documentElement.getAttribute("data-theme") === "dark";
    const textSecondary = isDark ? "#cfcfcf" : "#737373";
    const borderSubdued = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.10)";
    const lineColor = isDark ? "#ffffff" : "#171717";

    const series = points.map((p) => ({
      date: p.dateObj,
      value: p.combined || 0,
      point: p,
    }));

    // Always show the Y-axis; on narrow (mobile) widths use compact labels
    // (e.g. "$15K") and a tighter left margin so the axis values still fit.
    const isNarrow = width < 360;
    const margin = { top: 16, right: 24, bottom: 28, left: isNarrow ? 44 : 56 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;

    const xExtent = d3.extent(series, (d) => d.date);
    const x = d3
      .scaleTime()
      .domain(
        xExtent[0].getTime() === xExtent[1].getTime()
          ? [d3.timeDay.offset(xExtent[0], -1), d3.timeDay.offset(xExtent[1], 1)]
          : xExtent,
      )
      .range([margin.left, margin.left + innerWidth]);

    const yExtent = d3.extent(series, (d) => d.value);
    const yPad = Math.max((yExtent[1] - yExtent[0]) * 0.1, 1);
    const y = d3
      .scaleLinear()
      .domain([yExtent[0] - yPad, yExtent[1] + yPad])
      .range([margin.top + innerHeight, margin.top]);

    const svg = d3
      .select(root)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr("aria-label", "Basis account value history");

    const yTicks = y.ticks(isNarrow ? 3 : 4);
    svg
      .append("g")
      .selectAll("line")
      .data(yTicks)
      .join("line")
      .attr("x1", margin.left)
      .attr("x2", margin.left + innerWidth)
      .attr("y1", (d) => y(d))
      .attr("y2", (d) => y(d))
      .attr("stroke", borderSubdued)
      .attr("stroke-width", 1);

    svg
      .append("g")
      .selectAll("text")
      .data(yTicks)
      .join("text")
      .attr("x", margin.left - 8)
      .attr("y", (d) => y(d))
      .attr("dy", "0.32em")
      .attr("text-anchor", "end")
      .attr("font-size", isNarrow ? 10 : 11)
      .attr("fill", textSecondary)
      .text((d) => this._formatCurrency(d, { compact: isNarrow }));

    const xLabelTicks =
      series.length <= 2 ? series : [series[0], series[Math.floor(series.length / 2)], series[series.length - 1]];
    svg
      .append("g")
      .selectAll("text")
      .data(xLabelTicks)
      .join("text")
      .attr("x", (d) => x(d.date))
      .attr("y", margin.top + innerHeight + 18)
      .attr("text-anchor", "middle")
      .attr("font-size", 11)
      .attr("fill", textSecondary)
      .text((d) => d3.timeFormat("%b %d")(d.date));

    const line = d3
      .line()
      .x((d) => x(d.date))
      .y((d) => y(d.value))
      .curve(d3.curveMonotoneX);

    svg
      .append("path")
      .datum(series)
      .attr("fill", "none")
      .attr("stroke", lineColor)
      .attr("stroke-width", 2)
      .attr("stroke-linejoin", "round")
      .attr("stroke-linecap", "round")
      .attr("d", line);

    if (series.length === 1) {
      svg
        .append("circle")
        .attr("cx", x(series[0].date))
        .attr("cy", y(series[0].value))
        .attr("r", 4)
        .attr("fill", lineColor);
    }

    this._installTooltip(svg, series, x, y, margin, innerWidth, innerHeight, lineColor);
  }

  _installTooltip(svg, series, x, y, margin, innerWidth, innerHeight, lineColor) {
    if (!this._tooltip) {
      this._tooltip = document.createElement("div");
      this._tooltip.className = CHART_TOOLTIP_CLASSES;
      this._tooltip.style.display = "none";
      this.chartTarget.appendChild(this._tooltip);
    }
    const tooltip = this._tooltip;

    const crosshair = svg
      .append("line")
      .attr("y1", margin.top)
      .attr("y2", margin.top + innerHeight)
      .attr("stroke", lineColor)
      .attr("stroke-width", 1)
      .attr("stroke-dasharray", "3,3")
      .style("opacity", 0);

    const dot = svg
      .append("circle")
      .attr("r", 4)
      .attr("fill", lineColor)
      .style("opacity", 0);

    const bisect = d3.bisector((d) => d.date).center;

    svg
      .append("rect")
      .attr("x", margin.left)
      .attr("y", margin.top)
      .attr("width", Math.max(innerWidth, 0))
      .attr("height", Math.max(innerHeight, 0))
      .attr("fill", "transparent")
      .style("cursor", "crosshair")
      .on("pointermove", (event) => {
        const [mx] = d3.pointer(event);
        const date = x.invert(mx);
        const i = bisect(series, date);
        const d = series[i];
        if (!d) return;

        crosshair.attr("x1", x(d.date)).attr("x2", x(d.date)).style("opacity", 1);
        dot.attr("cx", x(d.date)).attr("cy", y(d.value)).style("opacity", 1);

        tooltip.innerHTML = this._tooltipHtml(d.point, d.value);
        tooltip.style.display = "block";

        const rect = this.chartTarget.getBoundingClientRect();
        const tipWidth = tooltip.offsetWidth;
        let left = x(d.date) + 12;
        if (left + tipWidth > rect.width) left = x(d.date) - tipWidth - 12;
        tooltip.style.left = `${left}px`;
        tooltip.style.top = `${margin.top}px`;
      })
      .on("pointerleave", () => {
        crosshair.style("opacity", 0);
        dot.style("opacity", 0);
        tooltip.style.display = "none";
      });
  }

  _tooltipHtml(point, combinedValue) {
    const row = (label, value) =>
      `<div class="flex items-center justify-between gap-4">
         <span class="text-secondary">${label}</span>
         <span class="${CHART_TOOLTIP_VALUE_CLASSES}">${this._formatCurrency(value)}</span>
       </div>`;

    const labels = this.labelsValue || {};
    const rows = [
      row(labels.spot || "weETH spot", point.spot || 0),
      point.lighter_account_value != null
        ? row(labels.lighter_account_value || "Lighter account value", point.lighter_account_value)
        : "",
      row(labels.short || "Perps short", point.short || 0),
      row(labels.funding || "Funding", point.funding || 0),
      row(labels.rewards || "Rewards", point.rewards || 0),
    ].filter(Boolean);

    return `
      <div class="${CHART_TOOLTIP_CONTEXT_CLASSES}">${point.date_formatted || point.date}</div>
      <div class="space-y-0.5">
        ${rows.join("")}
        <div class="flex items-center justify-between gap-4 pt-1 mt-1 border-t border-secondary">
          <span class="text-primary font-medium">${labels.combined || "Account value"}</span>
          <span class="${CHART_TOOLTIP_VALUE_CLASSES} text-primary">${this._formatCurrency(combinedValue)}</span>
        </div>
      </div>`;
  }

  _parseLocalDate(s) {
    if (!s) return null;
    const [yr, mo, da] = s.split("-").map(Number);
    return new Date(yr, mo - 1, da);
  }
}
