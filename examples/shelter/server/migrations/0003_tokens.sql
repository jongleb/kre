-- migrate:up
CREATE TABLE kre_tokens (
  id VARCHAR(26) NOT NULL PRIMARY KEY,
  owner VARCHAR(128) NOT NULL,
  hash VARCHAR(64) NOT NULL UNIQUE,
  abilities TEXT NOT NULL,
  created DOUBLE NOT NULL,
  INDEX (owner)
);

-- migrate:down
DROP TABLE kre_tokens;
