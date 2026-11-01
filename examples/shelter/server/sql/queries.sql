-- @credential_by_email
SELECT credentials.user_id, credentials.hash FROM credentials JOIN users ON users.id = credentials.user_id WHERE users.email = @email LIMIT 1;
-- @adopt_cat
UPDATE cats SET status = @status, owner_id = @owner_id WHERE id = @id AND status = @available;
-- @rename_cat
UPDATE cats SET name = @name WHERE id = @id;
