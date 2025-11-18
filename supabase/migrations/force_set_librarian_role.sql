    -- FORCE SET the librarian role

    UPDATE auth.users
    SET raw_user_meta_data = 
    CASE 
        WHEN raw_user_meta_data IS NULL THEN '{"role": "librarian"}'::jsonb
        ELSE raw_user_meta_data || '{"role": "librarian"}'::jsonb
    END
    WHERE email = 'phoenix.xd2925@gmail.com';

    -- Verify
    SELECT 
    email,
    raw_user_meta_data->>'role' as role,
    raw_user_meta_data
    FROM auth.users
    WHERE email = 'phoenix.xd2925@gmail.com';

    SELECT 'Role has been set! Now LOG OUT and LOG BACK IN to the app!' as instruction;
