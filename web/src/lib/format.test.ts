// 单元测试：format.ts 核心格式化函数
// 运行：bun test web/src/lib/format.test.ts
// (localStorage polyfill is provided by bunfig.toml → src/test-setup.ts)

import { describe, it, expect } from 'bun:test'
import { fmtBytes, fmtSpeed, fmtEta } from './format'

// ---------------------------------------------------------------------------
// fmtBytes
// ---------------------------------------------------------------------------

describe('fmtBytes', () => {
  it('returns "0 B" for zero', () => {
    expect(fmtBytes(0)).toBe('0 B')
  })

  it('returns "0 B" for negative values', () => {
    expect(fmtBytes(-100)).toBe('0 B')
  })

  it('returns "0 B" for NaN', () => {
    expect(fmtBytes(NaN)).toBe('0 B')
  })

  it('formats bytes without suffix', () => {
    expect(fmtBytes(512)).toBe('512 B')
  })

  it('formats kilobytes', () => {
    expect(fmtBytes(4096)).toBe('4 KB')
  })

  it('formats megabytes with one decimal when < 100', () => {
    expect(fmtBytes(1.5 * 1024 * 1024)).toBe('1.5 MB')
  })

  it('formats megabytes without decimal when >= 100', () => {
    expect(fmtBytes(512 * 1024 * 1024)).toBe('512 MB')
  })

  it('formats gigabytes with one decimal when < 100', () => {
    expect(fmtBytes(2.5 * 1024 * 1024 * 1024)).toBe('2.5 GB')
  })

  it('formats gigabytes without decimal when >= 100', () => {
    expect(fmtBytes(200 * 1024 * 1024 * 1024)).toBe('200 GB')
  })
})

// ---------------------------------------------------------------------------
// fmtSpeed
// ---------------------------------------------------------------------------

describe('fmtSpeed', () => {
  it('appends /s to fmtBytes result', () => {
    expect(fmtSpeed(0)).toBe('0 B/s')
    expect(fmtSpeed(1024 * 1024)).toBe('1.0 MB/s')
  })

  it('formats typical download speeds', () => {
    // 10 MB/s — the "< 100 ? one decimal : no decimal" rule applies
    expect(fmtSpeed(10 * 1024 * 1024)).toBe('10.0 MB/s')
  })
})

// ---------------------------------------------------------------------------
// fmtEta
// ---------------------------------------------------------------------------

describe('fmtEta', () => {
  it('returns "—" when speed is zero', () => {
    expect(fmtEta(1000, 0)).toBe('—')
  })

  it('returns "—" when remaining bytes is zero', () => {
    expect(fmtEta(0, 1000)).toBe('—')
  })

  it('returns "—" when remaining bytes is negative', () => {
    expect(fmtEta(-1, 1000)).toBe('—')
  })
})
