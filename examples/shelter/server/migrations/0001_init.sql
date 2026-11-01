-- migrate:up
CREATE TABLE users (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  role VARCHAR(16) NOT NULL
);

CREATE TABLE cats (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(64) NOT NULL,
  age BIGINT NOT NULL,
  status VARCHAR(16) NOT NULL,
  owner_id BIGINT NULL,
  INDEX (status),
  FOREIGN KEY (owner_id) REFERENCES users (id)
);

CREATE TABLE adoptions (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  cat_id BIGINT NOT NULL UNIQUE,
  user_id BIGINT NOT NULL,
  FOREIGN KEY (cat_id) REFERENCES cats (id),
  INDEX (user_id),
  FOREIGN KEY (user_id) REFERENCES users (id)
);

CREATE TABLE credentials (
  user_id BIGINT NOT NULL PRIMARY KEY,
  hash VARCHAR(255) NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users (id)
);

-- migrate:down
DROP TABLE credentials;
DROP TABLE adoptions;
DROP TABLE cats;
DROP TABLE users;
