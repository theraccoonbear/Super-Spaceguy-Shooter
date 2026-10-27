CREATE TABLE sss_telemetry (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    session    TEXT    NOT NULL,
    ev_time    INTEGER NOT NULL,
    event      TEXT    NOT NULL,
    player_id  TEXT    NOT NULL,
    data       TEXT    NOT NULL,
    created_at TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE scores (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    player_id   TEXT    NOT NULL,
    player_name TEXT    NOT NULL,
    score       INTEGER NOT NULL,
    wave        INTEGER NOT NULL,
    session     TEXT    NOT NULL,
    created_at  TEXT    NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX scores_score_desc ON scores (score DESC, id);
