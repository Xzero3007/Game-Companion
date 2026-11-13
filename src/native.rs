//! The C++ side: the Qt application, the overlay window on KDE's overlay
//! layer, and its input region (cpp/native.cpp).

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("native.h");
        /// Starts Qt, loads the QML and runs until the app quits.
        fn gc_run() -> i32;
        /// Asks the app to quit (from any thread).
        fn gc_quit();

        include!("icons.h");
        /// The tray icon at `size` px, ARGB32 in network byte order.
        fn gc_tray_icon(size: i32) -> Vec<u8>;
    }
}

pub fn run() -> i32 {
    ffi::gc_run()
}

pub fn quit() {
    ffi::gc_quit()
}

/// Called by Qt's aboutToQuit (cpp/native.cpp): takes the single-instance
/// socket file away. Not on a signal or a crash; the next start replaces it.
#[no_mangle]
pub extern "C" fn gc_about_to_quit() {
    crate::instance::remove_socket(&crate::instance::runtime_dir());
}

/// The tray icon in every size the tray offers (needs the Qt app).
pub fn tray_icons() -> Vec<(i32, Vec<u8>)> {
    crate::tray::SIZES.iter().map(|&size| (size, ffi::gc_tray_icon(size))).collect()
}
