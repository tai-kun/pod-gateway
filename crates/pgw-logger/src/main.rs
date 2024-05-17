use std::collections::HashSet;
use std::env;
use std::fs::{File, OpenOptions};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
struct Log<'a> {
    timestamp: u128, // UNIX epoch in milliseconds
    level: u8,
    message: &'a str,
}

enum State {
    Begin,
    Read,
    End,
}

enum Transport {
    Console,
    File(BufWriter<File>),
}

fn main() {
    let fifo_path = env::args().nth(1).unwrap();
    let fifo_file = OpenOptions::new().read(true).open(fifo_path).unwrap();
    let reader = BufReader::new(fifo_file);

    let transports = env::var("PGW_LOG_TRANSPORTS").unwrap_or_default();
    let transports: HashSet<_> = transports.split_whitespace().into_iter().collect();
    let mut transports: Vec<_> = transports
        .into_iter()
        .map(|t| match t {
            "console" => Transport::Console,
            "file" => Transport::File({
                let log_path = env::var("PGW_LOG_FILE_PATH").unwrap();
                let log_file = OpenOptions::new()
                    .append(true)
                    .create(true)
                    .open(log_path)
                    .unwrap();

                BufWriter::new(log_file)
            }),
            _ => panic!("Unknown transport: {}", t),
        })
        .collect();

    let mut timestamp: u128 = 0;
    let mut message = String::new();
    let mut level: u8 = 10;
    let mut state: State = State::End;

    for line in reader.lines() {
        if let Ok(line) = line {
            if line == "__CLOSE__" {
                break;
            }

            match state {
                State::End if line == "__BEGIN__" => {
                    if let Ok(duration) = SystemTime::now().duration_since(UNIX_EPOCH) {
                        timestamp = duration.as_millis();
                        state = State::Begin;
                    }
                }
                State::Begin => {
                    match line.as_str() {
                        "DEBUG" => level = 10,
                        "INFO" => level = 20,
                        "ERR" => level = 30,
                        _ => {
                            level = 10;
                            message = message + &line + "\n";
                        }
                    }
                    state = State::Read;
                }
                State::Read => {
                    let (end, line) = {
                        if line == "__END__" {
                            (true, "")
                        } else if line.ends_with("__END__") {
                            (true, line.trim_end_matches("__END__"))
                        } else {
                            (false, line.as_str())
                        }
                    };

                    if !line.is_empty() {
                        message.push_str(line);

                        if !end {
                            message.push('\n');
                        }
                    }

                    if end {
                        let log = Log {
                            timestamp,
                            level,
                            message: &message,
                        };

                        if let Ok(mut json) = serde_json::to_string(&log) {
                            json.push('\n');

                            for transport in &mut transports {
                                match transport {
                                    Transport::Console => {
                                        print!("{}", json);
                                    }
                                    Transport::File(writer) => {
                                        writer.write(json.as_bytes()).unwrap();
                                    }
                                }
                            }
                        }

                        timestamp = 0;
                        message.clear();
                        level = 10;
                        state = State::End;
                    }
                }
                _ => {
                    // Do nothing
                }
            }
        }
    }
}
