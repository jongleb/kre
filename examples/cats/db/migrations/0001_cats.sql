-- migrate:up
CREATE TABLE cats (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(64) NOT NULL,
  age BIGINT NOT NULL,
  breed VARCHAR(32) NOT NULL,
  INDEX (breed)
);

-- migrate:down
DROP TABLE cats;
