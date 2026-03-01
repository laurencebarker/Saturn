use axum::{
    extract::Query,
    response::{IntoResponse, Json},
};
use regex::RegexBuilder;
use serde::Deserialize;
use std::fs;
use std::path::Path;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use sysinfo::{Disks, Networks, System};
use tokio::process::Command;
use tracing::error;
use users::get_user_by_uid;

#[derive(Deserialize, Default)]
pub struct ProcQuery {
    proc_sort: Option<String>,
    proc_order: Option<String>,
    proc_user: Option<String>,
    proc_regex: Option<String>,
    proc_top: Option<usize>,
    proc_page: Option<usize>,
    proc_page_size: Option<usize>,
}

pub async fn get_system_data(Query(q): Query<ProcQuery>) -> impl IntoResponse {
    let cpu = match read_per_core_cpu().await {
        Ok(v) => v,
        Err(e) => {
            error!("cpu read error: {e}");
            vec![0.0]
        }
    };

    let mut sys = System::new();
    sys.refresh_memory();
    sys.refresh_cpu();
    sys.refresh_processes();

    let total_mem_kb = sys.total_memory() as f64;
    let avail_mem_kb = sys.available_memory() as f64;
    let used_mem_kb = (total_mem_kb - avail_mem_kb).max(0.0);

    let m_total_gb = total_mem_kb / 1024.0 / 1024.0;
    let m_used_gb = used_mem_kb / 1024.0 / 1024.0;
    let m_percent = if total_mem_kb > 0.0 {
        (used_mem_kb / total_mem_kb) * 100.0
    } else {
        0.0
    };

    let mut disks = Disks::new_with_refreshed_list();
    disks.refresh();
    let (d_total_gb, d_used_gb, d_percent) = pick_root_disk(&disks);
    let (d_read_bytes, d_write_bytes) = read_disk_io_totals();
    let (d_read_bps, d_write_bps) = calc_rate("disk", d_read_bytes, d_write_bytes);

    let mut networks = Networks::new_with_refreshed_list();
    networks.refresh();
    let (mut sent, mut recv) = sum_networks(&networks);
    if sent == 0 && recv == 0 {
        let (psent, precv) = read_net_dev_totals();
        if psent > 0 || precv > 0 {
            sent = psent;
            recv = precv;
        }
    }
    let (tx_bps, rx_bps) = calc_rate("net", sent, recv);

    let procs = list_procs_sysinfo(&sys, total_mem_kb, &q);
    let load = sysinfo::System::load_average();
    let uptime = sysinfo::System::uptime();
    let cpu_temp = read_cpu_temp_c();
    let swap_total_gb = sys.total_swap() as f64 / 1024.0 / 1024.0;
    let swap_used_gb = sys.used_swap() as f64 / 1024.0 / 1024.0;
    let swap_percent = if sys.total_swap() > 0 {
        (sys.used_swap() as f64 / sys.total_swap() as f64) * 100.0
    } else {
        0.0
    };

    Json(serde_json::json!({
        "cpu": cpu,
        "memory": { "percent": m_percent, "used": m_used_gb, "total": m_total_gb },
        "swap": { "percent": swap_percent, "used": swap_used_gb, "total": swap_total_gb },
        "disk": { "percent": d_percent, "used": d_used_gb, "total": d_total_gb, "read_bytes": d_read_bytes, "write_bytes": d_write_bytes, "read_bps": d_read_bps, "write_bps": d_write_bps },
        "network": { "sent": sent, "recv": recv, "tx_bps": tx_bps, "rx_bps": rx_bps },
        "load": { "one": load.one, "five": load.five, "fifteen": load.fifteen },
        "uptime": { "seconds": uptime },
        "temperature": { "cpu_c": cpu_temp },
        "processes": procs
    }))
}

pub async fn network_test() -> impl IntoResponse {
    let (sent0, recv0) = get_net_totals();
    let start = Instant::now();

    let urls = [
        "https://ash-speed.hetzner.com/10MB.bin",
        "https://proof.ovh.net/files/10Mb.dat",
        "https://speed.cloudflare.com/__down?bytes=10000000",
    ];
    let mut last_err = String::new();
    let mut ok = false;

    for url in urls {
        let out = Command::new("curl")
            .arg("-L")
            .arg("--silent")
            .arg("--show-error")
            .arg("--fail")
            .arg("--max-redirs")
            .arg("5")
            .arg("--output")
            .arg("/dev/null")
            .arg("--connect-timeout")
            .arg("5")
            .arg("--max-time")
            .arg("30")
            .arg(url)
            .output()
            .await;

        match out {
            Ok(o) if o.status.success() => {
                ok = true;
                break;
            }
            Ok(o) => {
                let stderr = String::from_utf8_lossy(&o.stderr).trim().to_string();
                if stderr.is_empty() {
                    last_err = format!("{} on {}", o.status, url);
                } else {
                    last_err = format!("{} on {} ({})", o.status, url, stderr);
                }
            }
            Err(e) => {
                last_err = format!("{} on {}", e, url);
            }
        }
    }

    let elapsed = start.elapsed().as_secs_f64().max(0.001);
    let (sent1, recv1) = get_net_totals();

    if ok {
        let tx_bps = ((sent1.saturating_sub(sent0)) as f64 / elapsed) as u64;
        let rx_bps = ((recv1.saturating_sub(recv0)) as f64 / elapsed) as u64;
        Json(serde_json::json!({
            "tx_bps": tx_bps,
            "rx_bps": rx_bps,
            "seconds": elapsed
        }))
    } else {
        Json(serde_json::json!({
            "error": format!("curl test failed: {}", if last_err.is_empty() { "no route succeeded".to_string() } else { last_err })
        }))
    }
}

async fn read_per_core_cpu() -> Result<Vec<f64>, String> {
    let a = read_proc_stat().await?;
    tokio::time::sleep(Duration::from_millis(120)).await;
    let b = read_proc_stat().await?;
    if a.len() != b.len() || a.is_empty() {
        return Ok(vec![0.0]);
    }

    let mut out = Vec::with_capacity(a.len());
    for (sa, sb) in a.iter().zip(b.iter()) {
        let d_idle = (sb.idle - sa.idle) as f64;
        let d_total = (sb.total - sa.total) as f64;
        let mut p = if d_total > 0.0 {
            (1.0 - d_idle / d_total) * 100.0
        } else {
            0.0
        };
        if p < 0.0 {
            p = 0.0;
        } else if p > 100.0 {
            p = 100.0;
        }
        out.push(p);
    }
    Ok(out)
}

#[derive(Clone, Copy)]
struct CpuSnap {
    idle: u64,
    total: u64,
}

async fn read_proc_stat() -> Result<Vec<CpuSnap>, String> {
    let data = tokio::fs::read_to_string("/proc/stat")
        .await
        .map_err(|e| e.to_string())?;
    let mut res = Vec::new();
    for line in data.lines() {
        if !line.starts_with("cpu") || line.starts_with("cpu ") {
            continue;
        }
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 6 {
            continue;
        }
        let mut vals = Vec::new();
        for p in &parts[1..] {
            if let Ok(v) = p.parse::<u64>() {
                vals.push(v);
            }
        }
        if vals.len() < 5 {
            continue;
        }
        let idle = vals[3] + vals[4];
        let total: u64 = vals.iter().sum();
        res.push(CpuSnap { idle, total });
    }
    Ok(res)
}

fn pick_root_disk(disks: &Disks) -> (f64, f64, f64) {
    let mut total = 0.0;
    let mut used = 0.0;

    if let Some(d) = disks.iter().find(|d| d.mount_point() == Path::new("/")) {
        total = d.total_space() as f64;
        used = (d.total_space() - d.available_space()) as f64;
    } else if let Some(d) = disks.iter().next() {
        total = d.total_space() as f64;
        used = (d.total_space() - d.available_space()) as f64;
    }

    let total_gb = total / 1024.0 / 1024.0 / 1024.0;
    let used_gb = used / 1024.0 / 1024.0 / 1024.0;
    let percent = if total > 0.0 {
        (used / total) * 100.0
    } else {
        0.0
    };
    (total_gb, used_gb, percent)
}

fn sum_networks(networks: &Networks) -> (u64, u64) {
    let mut sent = 0u64;
    let mut recv = 0u64;
    for (_name, data) in networks.iter() {
        sent += data.transmitted();
        recv += data.received();
    }
    (sent, recv)
}

fn get_net_totals() -> (u64, u64) {
    let mut networks = Networks::new_with_refreshed_list();
    networks.refresh();
    let (sent, recv) = sum_networks(&networks);
    if sent == 0 && recv == 0 {
        return read_net_dev_totals();
    }
    (sent, recv)
}

fn read_net_dev_totals() -> (u64, u64) {
    if let Ok(data) = fs::read_to_string("/proc/net/dev") {
        let mut sent = 0u64;
        let mut recv = 0u64;
        for line in data.lines().skip(2) {
            let parts: Vec<&str> = line.split(':').collect();
            if parts.len() != 2 {
                continue;
            }
            let stats: Vec<&str> = parts[1].split_whitespace().collect();
            if stats.len() >= 16 {
                recv += stats[0].parse::<u64>().unwrap_or(0);
                sent += stats[8].parse::<u64>().unwrap_or(0);
            }
        }
        return (sent, recv);
    }
    (0, 0)
}

fn read_cpu_temp_c() -> Option<f64> {
    if let Ok(entries) = fs::read_dir("/sys/class/thermal") {
        for entry in entries.flatten() {
            let path = entry.path().join("temp");
            if let Ok(s) = fs::read_to_string(&path) {
                if let Ok(raw) = s.trim().parse::<f64>() {
                    let c = if raw > 1000.0 { raw / 1000.0 } else { raw };
                    if c > 0.0 {
                        return Some(c);
                    }
                }
            }
        }
    }
    None
}

fn read_disk_io_totals() -> (u64, u64) {
    let dev = match root_device_name() {
        Some(d) => d,
        None => return (0, 0),
    };
    if let Ok(data) = fs::read_to_string("/proc/diskstats") {
        for line in data.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() < 14 {
                continue;
            }
            if parts[2] == dev {
                let sr = parts[5].parse::<u64>().unwrap_or(0);
                let sw = parts[9].parse::<u64>().unwrap_or(0);
                return (sr.saturating_mul(512), sw.saturating_mul(512));
            }
        }
    }
    (0, 0)
}

fn root_device_name() -> Option<String> {
    if let Ok(data) = fs::read_to_string("/proc/mounts") {
        for line in data.lines() {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 && parts[1] == "/" {
                let dev = parts[0];
                if dev.starts_with("/dev/") {
                    return Some(base_device_name(dev));
                }
            }
        }
    }
    None
}

fn base_device_name(dev: &str) -> String {
    let name = dev.trim_start_matches("/dev/");
    if name.starts_with("nvme") && name.contains('p') {
        return name.split('p').next().unwrap_or(name).to_string();
    }
    if name.starts_with("mmcblk") && name.contains('p') {
        return name.split('p').next().unwrap_or(name).to_string();
    }
    let trimmed = name.trim_end_matches(|c: char| c.is_ascii_digit());
    if trimmed.is_empty() {
        name.to_string()
    } else {
        trimmed.to_string()
    }
}

fn calc_rate(kind: &str, a: u64, b: u64) -> (u64, u64) {
    static LAST: OnceLock<Mutex<std::collections::HashMap<String, (u64, u64, u128)>>> =
        OnceLock::new();
    let map = LAST.get_or_init(|| Mutex::new(std::collections::HashMap::new()));
    let mut guard = map.lock().unwrap();

    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let entry = guard.entry(kind.to_string()).or_insert((a, b, now_ms));
    let (la, lb, lt) = *entry;
    let dt_ms = (now_ms.saturating_sub(lt)).max(1);

    let ra = a.saturating_sub(la) * 1000 / dt_ms as u64;
    let rb = b.saturating_sub(lb) * 1000 / dt_ms as u64;

    *entry = (a, b, now_ms);
    (ra, rb)
}

#[derive(Debug)]
struct ProcInfo {
    pid: i32,
    user: String,
    cpu: f64,
    mem_pct: f64,
    mem_mb: f64,
    command: String,
    cwd: String,
    start_time: u64,
}

fn list_procs_sysinfo(
    sys: &System,
    total_mem_kb: f64,
    q: &ProcQuery,
) -> Vec<serde_json::Value> {
    let mut out: Vec<ProcInfo> = Vec::new();
    for (pid, proc_) in sys.processes() {
        let pid_i32 = pid.as_u32() as i32;
        let user = proc_
            .user_id()
            .and_then(|u| u.to_string().parse::<u32>().ok())
            .and_then(|uid| get_user_by_uid(uid))
            .and_then(|u| u.name().to_str().map(|s| s.to_string()))
            .unwrap_or_else(|| "unknown".to_string());
        let cmd = if !proc_.cmd().is_empty() {
            proc_.cmd().join(" ")
        } else if let Some(exe) = proc_.exe() {
            if !exe.as_os_str().is_empty() {
                exe.display().to_string()
            } else {
                proc_.name().to_string()
            }
        } else {
            proc_.name().to_string()
        };
        let cwd = proc_
            .cwd()
            .map(|p| p.display().to_string())
            .unwrap_or_default();
        let start_time = proc_.start_time();

        let mem_kb = proc_.memory() as f64;
        let mem_pct = if total_mem_kb > 0.0 {
            (mem_kb / total_mem_kb) * 100.0
        } else {
            0.0
        };
        let cpu = proc_.cpu_usage() as f64;

        out.push(ProcInfo {
            pid: pid_i32,
            user,
            cpu,
            mem_pct,
            mem_mb: mem_kb / 1024.0,
            command: cmd,
            cwd,
            start_time,
        });
    }

    // Filters
    if let Some(u) = &q.proc_user {
        out.retain(|p| p.user == *u);
    }
    if let Some(r) = &q.proc_regex {
        if let Ok(re) = RegexBuilder::new(r).size_limit(1 << 16).build() {
            out.retain(|p| re.is_match(&p.command));
        }
    }

    // Sorting
    let sort = q.proc_sort.as_deref().unwrap_or("cpu");
    let desc = q.proc_order.as_deref().unwrap_or("desc") != "asc";
    out.sort_by(|a, b| match sort {
        "mem" => a
            .mem_pct
            .partial_cmp(&b.mem_pct)
            .unwrap_or(std::cmp::Ordering::Equal),
        "pid" => a.pid.cmp(&b.pid),
        "user" => a.user.cmp(&b.user),
        "command" => a.command.cmp(&b.command),
        "start" => a.start_time.cmp(&b.start_time),
        _ => a
            .cpu
            .partial_cmp(&b.cpu)
            .unwrap_or(std::cmp::Ordering::Equal),
    });
    if desc {
        out.reverse();
    }

    // Pagination / top
    if let Some(top) = q.proc_top {
        if out.len() > top {
            out.truncate(top);
        }
    } else if let (Some(page), Some(page_size)) = (q.proc_page, q.proc_page_size) {
        let start = page.saturating_mul(page_size);
        out = out.into_iter().skip(start).take(page_size).collect();
    } else if out.len() > 20 {
        out.truncate(20);
    }

    out.into_iter()
        .map(|p| {
            serde_json::json!({
                "pid": p.pid,
                "user": p.user,
                "cpu": p.cpu,
                "memory": p.mem_pct,
                "mem_mb": p.mem_mb,
                "command": p.command,
                "cwd": p.cwd,
                "start_time": p.start_time,
            })
        })
        .collect()
}
