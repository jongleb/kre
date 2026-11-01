-- @credential_by_email
SELECT credentials.user_id, credentials.hash FROM credentials JOIN users ON users.id = credentials.user_id WHERE users.email = @email LIMIT 1;
-- @adopt_cat
UPDATE cats SET status = @status, owner_id = @owner_id, version = version + 1 WHERE id = @id AND status = @available;
