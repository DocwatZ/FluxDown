// bun test setup file: polyfill browser globals unavailable in bun's JS engine.
// Referenced via "bun.test.preload" in package.json (or --preload flag).

// localStorage is accessed at module initialisation in i18n.tsx.
if (typeof globalThis.localStorage === 'undefined') {
  const _store: Record<string, string> = {}
  // @ts-expect-error intentional minimal stub
  globalThis.localStorage = {
    getItem: (k: string) => _store[k] ?? null,
    setItem: (k: string, v: string) => { _store[k] = v },
    removeItem: (k: string) => { delete _store[k] },
    clear: () => Object.keys(_store).forEach((k) => delete _store[k]),
  }
}
