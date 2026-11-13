//! Between the capture helper (the one program allowed to listen) and the
//! app: the helper writes each captured TCP segment to its stdout, the app
//! writes the port detector's state to the helper's stdin, one line at a
//! time. Nothing leaves this computer.
//!
//! A segment: its length (u32, little endian) and then
//! src port, dst port (u16), capture time (i64, ms), src and dst IPv4
//! (u32, 0 for none), TCP seq and ack (u32), the device's name (u8 length
//! and bytes) and the payload.

use std::io::{self, Read, Write};
use std::net::Ipv4Addr;

use crate::capture::captured_payload::CapturedPayload;

/// No segment is larger (libpcap's snapshot length is far below it).
const MAX_SEGMENT: usize = 1 << 20;

pub fn write_segment(out: &mut impl Write, p: &CapturedPayload) -> io::Result<()> {
    let device = p.device_name.as_deref().unwrap_or("").as_bytes();
    let device = &device[..device.len().min(255)];
    let mut body = Vec::with_capacity(33 + device.len() + p.data.len());
    body.extend_from_slice(&p.src_port.to_le_bytes());
    body.extend_from_slice(&p.dst_port.to_le_bytes());
    body.extend_from_slice(&p.captured_at_ms.to_le_bytes());
    body.extend_from_slice(&p.src_ip.map_or(0, u32::from).to_le_bytes());
    body.extend_from_slice(&p.dst_ip.map_or(0, u32::from).to_le_bytes());
    body.extend_from_slice(&p.tcp_seq.to_le_bytes());
    body.extend_from_slice(&p.tcp_ack.to_le_bytes());
    body.push(device.len() as u8);
    body.extend_from_slice(device);
    body.extend_from_slice(&p.data);
    out.write_all(&(body.len() as u32).to_le_bytes())?;
    out.write_all(&body)
}

/// The next segment, or None at the end of the stream.
pub fn read_segment(input: &mut impl Read) -> io::Result<Option<CapturedPayload>> {
    let mut len = [0u8; 4];
    match input.read_exact(&mut len) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e),
    }
    let len = u32::from_le_bytes(len) as usize;
    if !(29..=MAX_SEGMENT).contains(&len) {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "bad segment length"));
    }
    let mut body = vec![0u8; len];
    input.read_exact(&mut body)?;
    let u16_at = |i: usize| u16::from_le_bytes([body[i], body[i + 1]]);
    let u32_at = |i: usize| u32::from_le_bytes(body[i..i + 4].try_into().unwrap());
    let ip = |v: u32| (v != 0).then(|| Ipv4Addr::from(v));
    let device_len = body[28] as usize;
    if 29 + device_len > len {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "bad device length"));
    }
    let device = String::from_utf8_lossy(&body[29..29 + device_len]).into_owned();
    Ok(Some(CapturedPayload {
        src_port: u16_at(0),
        dst_port: u16_at(2),
        captured_at_ms: i64::from_le_bytes(body[4..12].try_into().unwrap()),
        src_ip: ip(u32_at(12)),
        dst_ip: ip(u32_at(16)),
        tcp_seq: u32_at(20),
        tcp_ack: u32_at(24),
        device_name: (!device.is_empty()).then_some(device),
        data: body[29 + device_len..].to_vec(),
    }))
}

/// What the app tells the helper: the locked port (if any), when the game
/// last parsed and when the port last sent (ms), and whether AION 2 runs.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct State {
    pub port: Option<u16>,
    pub last_parsed_ms: i64,
    pub last_from_port_ms: i64,
    pub game_running: bool,
}

impl State {
    pub fn line(&self) -> String {
        format!(
            "S {} {} {} {}\n",
            self.port.unwrap_or(0),
            self.last_parsed_ms,
            self.last_from_port_ms,
            u8::from(self.game_running)
        )
    }

    pub fn parse(line: &str) -> Option<State> {
        let mut parts = line.split_whitespace();
        if parts.next()? != "S" {
            return None;
        }
        let port: u16 = parts.next()?.parse().ok()?;
        let state = State {
            port: (port != 0).then_some(port),
            last_parsed_ms: parts.next()?.parse().ok()?,
            last_from_port_ms: parts.next()?.parse().ok()?,
            game_running: parts.next()? == "1",
        };
        parts.next().is_none().then_some(state)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_segment_comes_back_as_it_went() {
        let p = CapturedPayload {
            src_port: 13328,
            dst_port: 50123,
            data: vec![1, 2, 3, 0x0e, 0, 0x36],
            device_name: Some("enp5s0".into()),
            captured_at_ms: 1_794_000_000_123,
            src_ip: Some(Ipv4Addr::new(10, 1, 2, 3)),
            dst_ip: None,
            tcp_seq: 7,
            tcp_ack: 9,
        };
        let mut buf = Vec::new();
        write_segment(&mut buf, &p).unwrap();
        write_segment(&mut buf, &CapturedPayload { device_name: None, data: vec![], ..p.clone() }).unwrap();
        let mut r = &buf[..];
        let a = read_segment(&mut r).unwrap().unwrap();
        assert_eq!((a.src_port, a.dst_port, a.captured_at_ms), (13328, 50123, 1_794_000_000_123));
        assert_eq!((a.src_ip, a.dst_ip, a.tcp_seq, a.tcp_ack), (p.src_ip, None, 7, 9));
        assert_eq!((a.device_name.as_deref(), a.data.as_slice()), (Some("enp5s0"), &p.data[..]));
        let b = read_segment(&mut r).unwrap().unwrap();
        assert!(b.device_name.is_none() && b.data.is_empty());
        assert!(read_segment(&mut r).unwrap().is_none());
    }

    #[test]
    fn a_broken_stream_is_refused() {
        let mut r: &[u8] = &[255, 255, 255, 255, 0];
        assert!(read_segment(&mut r).is_err());
    }

    #[test]
    fn the_state_line_reads_back() {
        let s = State { port: Some(13328), last_parsed_ms: 5, last_from_port_ms: 6, game_running: true };
        assert_eq!(State::parse(&s.line()), Some(s));
        assert_eq!(State::parse("S 0 0 0 0"), Some(State::default()));
        assert_eq!(State::parse("S 1 2 3"), None);
        assert_eq!(State::parse("X 1 2 3 1"), None);
    }
}
