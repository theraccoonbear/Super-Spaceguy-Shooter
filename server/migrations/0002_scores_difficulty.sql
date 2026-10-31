ALTER TABLE scores ADD COLUMN difficulty TEXT NOT NULL DEFAULT 'normal';

CREATE INDEX scores_difficulty_score_desc ON scores (difficulty, score DESC, id);
