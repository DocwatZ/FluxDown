//! 结构化启动横幅：打印服务器版本、数据目录、下载目录可写性、Docker/Unraid 检测等
//! 到 stderr 和日志文件，方便运维排查问题。
//!
//! 零新依赖：Docker/Unraid 检测、磁盘信息均通过已有 `fs2` + 标准库实现。

use std::path::Path;

use fluxdown_engine::log_info;

use crate::config::mask_token;

/// 打印结构化启动横幅。
///
/// - `version` — 服务器版本字符串
/// - `bind` — 监听地址（如 `"0.0.0.0:17800"`）
/// - `data_dir` — 数据目录路径
/// - `save_dir` — 当前默认下载目录
/// - `token` — 管理 token（仅打印前 8 字符 + `…`）
pub fn print_startup_banner(
    version: &str,
    bind: &str,
    data_dir: &Path,
    save_dir: &str,
    token: &str,
) {
    let sep = "═══════════════════════════════════════════════════════════";
    let thin = "───────────────────────────────────────────────────────────";

    // --- runtime environment detection (zero new deps) ------------------

    let in_docker = detect_docker();
    let in_unraid = detect_unraid();
    let puid = std::env::var("PUID").unwrap_or_default();
    let pgid = std::env::var("PGID").unwrap_or_default();
    let os_info = detect_os();

    let dir_writable = probe_writable(save_dir);
    let (disk_free, disk_total) = disk_stats(save_dir);

    // Mask token: show first 8 chars + ellipsis.
    let token_display = mask_token(token);

    // --- print to stderr -------------------------------------------------

    eprintln!("{sep}");
    eprintln!("  FluxDown Server v{version}");
    eprintln!("  Build: {}", build_info());
    eprintln!("{thin}");
    eprintln!("  Data dir:      {}", data_dir.display());
    eprintln!(
        "  Download dir:  {} {}",
        save_dir,
        if dir_writable { "✓" } else { "✗ (not writable!)" }
    );
    eprintln!("  Bind:          {bind}");
    eprintln!("  Web UI:        http://{bind}/");
    eprintln!("  API docs:      http://{bind}/api/v1/docs");
    eprintln!("{thin}");
    eprintln!("  Auth:          token ({token_display})");
    if in_docker {
        let puid_pgid = if puid.is_empty() && pgid.is_empty() {
            "(PUID/PGID not set)".to_string()
        } else {
            format!("PUID={puid}, PGID={pgid}")
        };
        eprintln!("  Container:     Docker ({puid_pgid})");
    }
    if in_unraid {
        eprintln!("  Unraid:        detected");
    }
    if !os_info.is_empty() {
        eprintln!("  OS:            {os_info}");
    }
    if let Some((free, total)) = disk_free.zip(disk_total) {
        eprintln!(
            "  Disk free:     {} / {}",
            fmt_bytes(free),
            fmt_bytes(total)
        );
        if free < 100 * 1024 * 1024 {
            eprintln!("  ⚠ CRITICAL: Less than 100 MB disk space remaining!");
        } else if free < 1024 * 1024 * 1024 {
            eprintln!("  ⚠ WARNING: Less than 1 GB disk space remaining.");
        }
    }
    eprintln!("{sep}");

    // --- also write to log file -----------------------------------------
    log_info!(
        "[server] startup: v{} bind={} data_dir={} save_dir={} docker={} unraid={}",
        version,
        bind,
        data_dir.display(),
        save_dir,
        in_docker,
        in_unraid,
    );
    if !dir_writable {
        log_info!(
            "[server] WARNING: download directory is not writable: {}",
            save_dir
        );
    }
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// Returns `true` when running inside a Docker container.
///
/// Heuristic: `/.dockerenv` exists OR `/proc/self/cgroup` contains "docker".
fn detect_docker() -> bool {
    if Path::new("/.dockerenv").exists() {
        return true;
    }
    std::fs::read_to_string("/proc/self/cgroup")
        .map(|s| s.contains("docker"))
        .unwrap_or(false)
}

/// Returns `true` when running on Unraid.
///
/// Heuristic: `/boot/config/plugins/dynamix` directory exists.
fn detect_unraid() -> bool {
    Path::new("/boot/config/plugins/dynamix").is_dir()
}

/// Returns a brief OS description string (best-effort, never panics).
fn detect_os() -> String {
    let os = std::env::consts::OS;
    // Try to read /etc/os-release for distro name on Linux.
    if os == "linux" {
        if let Ok(s) = std::fs::read_to_string("/etc/os-release") {
            let name = s
                .lines()
                .find(|l| l.starts_with("PRETTY_NAME="))
                .and_then(|l| l.split('=').nth(1))
                .map(|v| v.trim_matches('"').to_string());
            if let Some(name) = name {
                return format!("Linux ({name})");
            }
        }
        return "Linux".to_string();
    }
    os.to_string()
}

/// Returns build information: git short SHA from `FLUXDOWN_BUILD_SHA` env at
/// compile time, or `"(dev)"` when not set.
fn build_info() -> &'static str {
    match option_env!("FLUXDOWN_BUILD_SHA") {
        Some(sha) if !sha.is_empty() => sha,
        _ => "(dev)",
    }
}

/// Probe whether the directory is writable by creating and removing a temp file.
fn probe_writable(dir: &str) -> bool {
    let probe = Path::new(dir).join(".fluxdown-probe");
    let ok = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&probe)
        .is_ok();
    let _ = std::fs::remove_file(&probe);
    ok
}

/// Returns (free_bytes, total_bytes) for the filesystem containing `dir`.
fn disk_stats(dir: &str) -> (Option<u64>, Option<u64>) {
    let p = Path::new(dir);
    let free = fs2::available_space(p).ok();
    let total = fs2::total_space(p).ok();
    (free, total)
}

/// Format bytes as human-readable string (GiB / MiB / KiB / B).
fn fmt_bytes(bytes: u64) -> String {
    const GIB: u64 = 1024 * 1024 * 1024;
    const MIB: u64 = 1024 * 1024;
    const KIB: u64 = 1024;
    if bytes >= GIB {
        format!("{:.1} GiB", bytes as f64 / GIB as f64)
    } else if bytes >= MIB {
        format!("{:.1} MiB", bytes as f64 / MIB as f64)
    } else if bytes >= KIB {
        format!("{:.1} KiB", bytes as f64 / KIB as f64)
    } else {
        format!("{bytes} B")
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {
    use super::fmt_bytes;

    #[test]
    fn fmt_bytes_gib() {
        assert_eq!(fmt_bytes(2 * 1024 * 1024 * 1024), "2.0 GiB");
    }

    #[test]
    fn fmt_bytes_mib() {
        assert_eq!(fmt_bytes(512 * 1024 * 1024), "512.0 MiB");
    }

    #[test]
    fn fmt_bytes_kib() {
        assert_eq!(fmt_bytes(4096), "4.0 KiB");
    }

    #[test]
    fn fmt_bytes_small() {
        assert_eq!(fmt_bytes(500), "500 B");
    }
}
