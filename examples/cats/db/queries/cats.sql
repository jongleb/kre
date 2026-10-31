-- @all
SELECT id, name, age, breed FROM cats ORDER BY id LIMIT @limit;
-- @by_id
SELECT id, name, age, breed FROM cats WHERE id = @id;
-- @insert
INSERT INTO cats (name, age, breed) VALUES (@name, @age, @breed);
-- @drop
DROP TABLE IF EXISTS cats;
