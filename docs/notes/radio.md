# Radio

Moved word for word from CLAUDE.md (2026-11-16); read it before working on this part.

- The radio (`src/radio.rs`): the user's mpv as a child (`--idle`, JSON IPC
  on a socket, `--ytdl=no`, killed with the app through PR_SET_PDEATHSIG);
  `Player::load` refuses any address whose host is not in the station
  list. mpv's volume is cubic: `mpv_volume` maps the bar like a browser.
  A station that plays on none of its addresses is remembered
  (`settings.radio.dead`), greyed and listed last, hidden by the switch
  right of the tabs (`hide_dead`); playing again clears it (MN,
  2026-11-14).
