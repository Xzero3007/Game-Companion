//! The YouTube library for QML (`Library` singleton): playlists with the
//! quick bookmark, and what was watched and where it stopped. All on this
//! computer (`library.rs`).

use std::pin::Pin;

use cxx_qt_lib::QString;
use serde_json::{json, Value};

use crate::library::{self, Video};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        /// The playlists: JSON `[{id, name, count, picture, created, updated,
        /// played, quick, titles}]`.
        #[qproperty(QString, playlists)]
        /// Raised on every change (marks on the lists follow it).
        #[qproperty(i32, revision)]
        /// Raised when a playlist's videos change (an open playlist loads again).
        #[qproperty(i32, lists_revision)]
        type Library = super::LibraryRust;

        /// A new playlist; its id ("" if the name is empty).
        #[qinvokable]
        fn create(self: Pin<&mut Library>, name: &QString) -> QString;
        #[qinvokable]
        fn rename(self: Pin<&mut Library>, id: &QString, name: &QString);
        #[qinvokable]
        fn remove_playlist(self: Pin<&mut Library>, id: &QString);
        /// Makes a playlist the one the bookmark fills.
        #[qinvokable]
        fn make_quick(self: Pin<&mut Library>, id: &QString);
        /// Adds a video (the list's JSON) to a playlist.
        #[qinvokable]
        fn add_to(self: Pin<&mut Library>, id: &QString, video: &QString);
        #[qinvokable]
        fn remove_from(self: Pin<&mut Library>, id: &QString, video: &QString);
        #[qinvokable]
        fn move_in(self: Pin<&mut Library>, id: &QString, from: i32, to: i32);
        /// A playlist was started (for "last played").
        #[qinvokable]
        fn played(self: Pin<&mut Library>, id: &QString);
        /// The bookmark: in the quick list or out (switched); true if in now.
        #[qinvokable]
        fn toggle_quick(self: Pin<&mut Library>, video: &QString) -> bool;
        /// A video's marks: JSON `{"p": 0..1, "done", "quick", "lists": [ids]}`.
        #[qinvokable]
        fn mark(self: &Library, id: &QString) -> QString;
        /// A playlist's videos (list JSON).
        #[qinvokable]
        fn videos(self: &Library, id: &QString) -> QString;
        /// Where a video stopped: kept for later (the window says it every
        /// few seconds while it plays, and when it closes).
        #[qinvokable]
        fn record(self: Pin<&mut Library>, video: &QString, position: f64, length: f64);
        /// Where to start a video again (0 from the start).
        #[qinvokable]
        fn resume_at(self: &Library, id: &QString) -> f64;
        #[qinvokable]
        fn set_watched(self: Pin<&mut Library>, video: &QString, done: bool);
        #[qinvokable]
        fn forget(self: Pin<&mut Library>, id: &QString);
        #[qinvokable]
        fn clear_history(self: Pin<&mut Library>);
        /// Asked by the Streams object after taking FreeTube over.
        #[qinvokable]
        fn refresh(self: Pin<&mut Library>);
    }
}

pub struct LibraryRust {
    playlists: QString,
    revision: i32,
    lists_revision: i32,
}

impl Default for LibraryRust {
    fn default() -> Self {
        let demo = std::env::var("GC_DEMO").unwrap_or_default();
        if demo.contains("streams") {
            library::demo();
        }
        Self { playlists: QString::from(&library::read(|l| l.summary()).to_string()), revision: 0, lists_revision: 0 }
    }
}

fn video_of(text: &QString) -> Option<Video> {
    serde_json::from_str::<Value>(&text.to_string()).ok().and_then(|v| Video::from_json(&v))
}

impl qobject::Library {
    /// After a change: the playlists again, and the revisions raised.
    fn changed(mut self: Pin<&mut Self>, lists: bool) {
        let summary = library::read(|l| l.summary()).to_string();
        self.as_mut().set_playlists(QString::from(&summary));
        let r = *self.revision() + 1;
        self.as_mut().set_revision(r);
        if lists {
            let r = *self.lists_revision() + 1;
            self.set_lists_revision(r);
        }
    }

    fn create(self: Pin<&mut Self>, name: &QString) -> QString {
        let id = library::change(|l| l.create(&name.to_string()));
        self.changed(false);
        QString::from(&id)
    }

    fn rename(self: Pin<&mut Self>, id: &QString, name: &QString) {
        if library::change(|l| l.rename(&id.to_string(), &name.to_string())) {
            self.changed(false);
        }
    }

    fn remove_playlist(self: Pin<&mut Self>, id: &QString) {
        if library::change(|l| l.delete(&id.to_string())) {
            self.changed(true);
        }
    }

    fn make_quick(self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        library::change(|l| {
            if l.playlist(&id).is_some() {
                l.quick = id;
            }
        });
        self.changed(false);
    }

    fn add_to(self: Pin<&mut Self>, id: &QString, video: &QString) {
        let Some(v) = video_of(video) else { return };
        if library::change(|l| l.add(&id.to_string(), v)) {
            self.changed(true);
        }
    }

    fn remove_from(self: Pin<&mut Self>, id: &QString, video: &QString) {
        if library::change(|l| l.remove(&id.to_string(), &video.to_string())) {
            self.changed(true);
        }
    }

    fn move_in(self: Pin<&mut Self>, id: &QString, from: i32, to: i32) {
        if from < 0 || to < 0 {
            return;
        }
        if library::change(|l| l.move_video(&id.to_string(), from as usize, to as usize)) {
            self.changed(true);
        }
    }

    fn played(self: Pin<&mut Self>, id: &QString) {
        library::change(|l| l.mark_played(&id.to_string()));
        self.changed(false);
    }

    fn toggle_quick(self: Pin<&mut Self>, video: &QString) -> bool {
        let Some(v) = video_of(video) else { return false };
        let on = library::change(|l| l.toggle_quick(v));
        self.changed(true);
        on
    }

    fn mark(&self, id: &QString) -> QString {
        let id = id.to_string();
        let j = library::read(|l| {
            let (p, done) = l.progress(&id);
            json!({ "p": p, "done": done, "quick": l.in_quick(&id), "lists": l.holding(&id) })
        });
        QString::from(&j.to_string())
    }

    fn videos(&self, id: &QString) -> QString {
        let id = id.to_string();
        let list: Vec<Value> = library::read(|l| l.playlist(&id).map(|p| p.videos.iter().map(|v| v.to_json()).collect()).unwrap_or_default());
        QString::from(&Value::Array(list).to_string())
    }

    fn record(self: Pin<&mut Self>, video: &QString, position: f64, length: f64) {
        let Some(v) = video_of(video) else { return };
        library::change(|l| l.record(v, position, length));
        self.changed(false);
    }

    fn resume_at(&self, id: &QString) -> f64 {
        library::read(|l| l.resume_at(&id.to_string()))
    }

    fn set_watched(self: Pin<&mut Self>, video: &QString, done: bool) {
        let Some(v) = video_of(video) else { return };
        library::change(|l| l.set_done(v, done));
        self.changed(false);
    }

    fn forget(self: Pin<&mut Self>, id: &QString) {
        library::change(|l| l.forget(&id.to_string()));
        self.changed(false);
    }

    fn clear_history(self: Pin<&mut Self>) {
        library::change(|l| l.history.clear());
        self.changed(false);
    }

    fn refresh(self: Pin<&mut Self>) {
        self.changed(true);
    }
}
