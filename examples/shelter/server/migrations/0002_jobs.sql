-- migrate:up
CREATE TABLE kre_jobs (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  queue VARCHAR(64) NOT NULL,
  payload TEXT NOT NULL,
  status VARCHAR(16) NOT NULL,
  attempts BIGINT NOT NULL,
  run_at DOUBLE NOT NULL,
  locked_until DOUBLE NULL,
  last_error TEXT NULL,
  INDEX (run_at)
);

-- migrate:down
DROP TABLE kre_jobs;
