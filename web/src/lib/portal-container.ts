/**
 * Returns the stable portal container element for all Radix UI Dialog portals.
 *
 * Using a dedicated element (rather than `document.body` directly) prevents the
 * "removeChild: node is not a child of this node" error that occurs in React 19
 * concurrent mode when multiple portals open/close in quick succession — for
 * example when the New Download dialog closes at the same time the BT file
 * selection dialog opens after submitting a magnet link.
 *
 * The element is declared in `index.html` as `<div id="dialog-root">` so it is
 * always present before any React render.  Falls back to `document.body` for
 * environments where the element may be absent (tests, SSR stubs).
 */
export function getDialogRoot(): HTMLElement {
  return document.getElementById('dialog-root') ?? document.body
}
