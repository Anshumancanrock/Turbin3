use anchor_lang::prelude::*;

#[constant]
pub const COUNTER_SEED: &[u8] = b"counter";

#[constant]
pub const HELLO_WORLD_LAMPORTS: u64 = 1;

#[constant]
pub const MAX_COUNT: u64 = 10;

/// Recorded by the `withdraw` CPI. Registration `init`s the account, so a
/// second withdraw from the same wallet fails.
#[constant]
pub const GITHUB_USERNAME: &str = "Anshumancanrock";
