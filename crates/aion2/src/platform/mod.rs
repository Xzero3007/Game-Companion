//! What the meter's capture asked of the platform, for Linux alone.

pub mod pcap;

/// Whether AION 2 runs: the meter looked for its window; here the host says
/// it (the app from its game detection, the capture helper from the app).
pub mod window_detector {
    use std::sync::atomic::{AtomicBool, Ordering};

    static RUNNING: AtomicBool = AtomicBool::new(false);

    pub fn set_running(running: bool) {
        RUNNING.store(running, Ordering::Relaxed);
    }

    /// The meter listed look-alike windows for its log; nothing here.
    pub fn describe_candidates() -> Vec<String> {
        Vec::new()
    }

    pub fn find_aion2_window_title() -> Option<String> {
        RUNNING.load(Ordering::Relaxed).then(|| "AION2".to_string())
    }
}

/// How much the client sent last (its length alone: what the client sends is
/// encrypted), for whoever wants to know whether the player moves.
static CLIENT_SENT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

type SentHook = std::sync::Arc<dyn Fn(usize) + Send + Sync>;
static SENT_HOOK: std::sync::RwLock<Option<SentHook>> = std::sync::RwLock::new(None);

pub fn client_sent(bytes: usize) {
    CLIENT_SENT.fetch_add(bytes as u64, std::sync::atomic::Ordering::Relaxed);
    let hook = SENT_HOOK.read().ok().and_then(|h| h.clone());
    if let Some(hook) = hook {
        hook(bytes);
    }
}

/// Who hears of each time the client sent (the world's movement guess).
pub fn on_client_sent(hook: Option<SentHook>) {
    if let Ok(mut slot) = SENT_HOOK.write() {
        *slot = hook;
    }
}

/// Bytes the client has sent to the game's server since the start.
pub fn client_bytes() -> u64 {
    CLIENT_SENT.load(std::sync::atomic::Ordering::Relaxed)
}
