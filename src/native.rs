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
    }
}

pub fn run() -> i32 {
    ffi::gc_run()
}

pub fn quit() {
    ffi::gc_quit()
}
