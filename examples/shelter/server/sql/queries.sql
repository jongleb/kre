-- @user_by_email
SELECT id, email, role FROM users WHERE email = @email;
-- @credential_by_email
SELECT credentials.user_id, credentials.hash FROM credentials JOIN users ON users.id = credentials.user_id WHERE users.email = @email LIMIT 1;
-- @cats_with_status
SELECT id, name, age, status, owner_id FROM cats WHERE status = @status ORDER BY id;
-- @adopt_cat
UPDATE cats SET status = @status, owner_id = @owner_id WHERE id = @id AND status = @available;
-- @rename_cat
UPDATE cats SET name = @name WHERE id = @id;
-- @adoptions_of
SELECT id, cat_id, user_id FROM adoptions WHERE user_id = @user_id ORDER BY id;
