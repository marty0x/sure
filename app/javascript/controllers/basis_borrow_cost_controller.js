import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dollar", "percent"]

  toggle() {
    this.dollarTarget.classList.toggle("hidden")
    this.percentTarget.classList.toggle("hidden")
  }
}
