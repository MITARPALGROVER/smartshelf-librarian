-- Book Processing Functions (Weight Change Based)
-- Simplified logic: Just detect weight changes, no exact calibration needed

-- Function: Process Book Issue (called by ESP8266 when weight decreases)
CREATE OR REPLACE FUNCTION process_book_issue(
  p_unlock_event_id UUID,
  p_user_id UUID,
  p_action TEXT DEFAULT 'pickup'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_book_id UUID;
  v_shelf_id UUID;
  v_issued_book_id UUID;
  v_result JSON;
BEGIN
  -- Get book and shelf from unlock event
  SELECT book_id, shelf_id
  INTO v_book_id, v_shelf_id
  FROM door_unlock_events
  WHERE id = p_unlock_event_id;
  
  IF v_book_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'No book found for unlock event'
    );
  END IF;
  
  -- Check if book is available
  IF EXISTS (
    SELECT 1 FROM issued_books
    WHERE book_id = v_book_id
      AND returned_at IS NULL
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Book is already issued'
    );
  END IF;
  
  -- Create issued book record
  INSERT INTO issued_books (
    book_id,
    user_id,
    issued_at,
    due_date,
    status,
    shelf_id,
    unlock_event_id
  ) VALUES (
    v_book_id,
    p_user_id,
    NOW(),
    NOW() + INTERVAL '14 days',
    'issued',
    v_shelf_id,
    p_unlock_event_id
  )
  RETURNING id INTO v_issued_book_id;
  
  -- Update book status
  UPDATE books
  SET status = 'issued'
  WHERE id = v_book_id;
  
  -- Update unlock event
  UPDATE door_unlock_events
  SET 
    actual_action = p_action,
    completed_at = NOW()
  WHERE id = p_unlock_event_id;
  
  -- Send notification to user
  INSERT INTO notifications (
    user_id,
    title,
    message,
    type,
    related_book_id
  ) VALUES (
    p_user_id,
    'Book Issued',
    'Your book has been successfully issued. Due date: ' || 
      TO_CHAR(NOW() + INTERVAL '14 days', 'DD Mon YYYY'),
    'info',
    v_book_id
  );
  
  -- Notify librarians
  INSERT INTO notifications (
    user_id,
    title,
    message,
    type,
    related_book_id
  )
  SELECT 
    ur.user_id,
    'Book Issued',
    'A book was issued via weight detection',
    'info',
    v_book_id
  FROM user_roles ur
  WHERE ur.role = 'librarian';
  
  RETURN json_build_object(
    'success', true,
    'issued_book_id', v_issued_book_id,
    'book_id', v_book_id,
    'action', 'issued'
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;

-- Function: Process Book Return (called by ESP8266 when weight increases)
CREATE OR REPLACE FUNCTION process_book_return(
  p_unlock_event_id UUID,
  p_user_id UUID,
  p_action TEXT DEFAULT 'return'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_book_id UUID;
  v_shelf_id UUID;
  v_issued_book_id UUID;
  v_result JSON;
BEGIN
  -- Get book and shelf from unlock event
  SELECT book_id, shelf_id
  INTO v_book_id, v_shelf_id
  FROM door_unlock_events
  WHERE id = p_unlock_event_id;
  
  IF v_book_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'No book found for unlock event'
    );
  END IF;
  
  -- Find the issued book record
  SELECT id INTO v_issued_book_id
  FROM issued_books
  WHERE book_id = v_book_id
    AND user_id = p_user_id
    AND returned_at IS NULL
  ORDER BY issued_at DESC
  LIMIT 1;
  
  IF v_issued_book_id IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'No active issue found for this book and user'
    );
  END IF;
  
  -- Mark book as returned
  UPDATE issued_books
  SET 
    returned_at = NOW(),
    status = 'returned',
    return_shelf_id = v_shelf_id
  WHERE id = v_issued_book_id;
  
  -- Update book status
  UPDATE books
  SET 
    status = 'available',
    current_shelf_id = v_shelf_id
  WHERE id = v_book_id;
  
  -- Update unlock event
  UPDATE door_unlock_events
  SET 
    actual_action = p_action,
    completed_at = NOW()
  WHERE id = p_unlock_event_id;
  
  -- Send notification to user
  INSERT INTO notifications (
    user_id,
    title,
    message,
    type,
    related_book_id
  ) VALUES (
    p_user_id,
    'Book Returned',
    'Your book has been successfully returned. Thank you!',
    'info',
    v_book_id
  );
  
  -- Notify librarians
  INSERT INTO notifications (
    user_id,
    title,
    message,
    type,
    related_book_id
  )
  SELECT 
    ur.user_id,
    'Book Returned',
    'A book was returned via weight detection',
    'info',
    v_book_id
  FROM user_roles ur
  WHERE ur.role = 'librarian';
  
  RETURN json_build_object(
    'success', true,
    'issued_book_id', v_issued_book_id,
    'book_id', v_book_id,
    'action', 'returned'
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION process_book_issue TO anon, authenticated;
GRANT EXECUTE ON FUNCTION process_book_return TO anon, authenticated;

COMMENT ON FUNCTION process_book_issue IS 'Called by ESP8266 when significant weight decrease detected (book taken)';
COMMENT ON FUNCTION process_book_return IS 'Called by ESP8266 when significant weight increase detected (book returned)';
