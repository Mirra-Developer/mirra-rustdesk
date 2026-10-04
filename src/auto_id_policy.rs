#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum OnlineState {
    Online,
    Offline,
    Unreachable,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Resolution {
    Selected(usize),
    Offline,
    Unavailable,
    Conflict,
}

pub fn select_server(states: &[OnlineState]) -> Resolution {
    let mut selected = None;
    for (index, state) in states.iter().enumerate() {
        if *state == OnlineState::Online {
            if selected.is_some() {
                return Resolution::Conflict;
            }
            selected = Some(index);
        }
    }
    match selected {
        Some(index) => Resolution::Selected(index),
        None if states.is_empty() || states.contains(&OnlineState::Unreachable) => {
            Resolution::Unavailable
        }
        None => Resolution::Offline,
    }
}

pub fn decode_online_states(bytes: &[u8], count: usize) -> Option<Vec<OnlineState>> {
    if bytes.len() < count.div_ceil(8) {
        return None;
    }
    Some(
        (0..count)
            .map(|index| {
                if bytes[index / 8] & (1 << (7 - index % 8)) != 0 {
                    OnlineState::Online
                } else {
                    OnlineState::Offline
                }
            })
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn routes_only_to_the_unique_online_server() {
        use OnlineState::*;
        for (states, expected) in [
            ([Online, Offline], Resolution::Selected(0)),
            ([Offline, Online], Resolution::Selected(1)),
            ([Online, Unreachable], Resolution::Selected(0)),
            ([Unreachable, Online], Resolution::Selected(1)),
            ([Online, Online], Resolution::Conflict),
            ([Offline, Offline], Resolution::Offline),
            ([Offline, Unreachable], Resolution::Unavailable),
            ([Unreachable, Offline], Resolution::Unavailable),
            ([Unreachable, Unreachable], Resolution::Unavailable),
        ] {
            assert_eq!(select_server(&states), expected);
        }
    }

    #[test]
    fn decodes_batched_states_across_byte_boundaries() {
        let states = decode_online_states(&[0b10000001, 0b10000000], 9).unwrap();
        assert_eq!(states[0], OnlineState::Online);
        assert_eq!(states[1], OnlineState::Offline);
        assert_eq!(states[7], OnlineState::Online);
        assert_eq!(states[8], OnlineState::Online);
        assert!(decode_online_states(&[0xff], 9).is_none());
    }
}
