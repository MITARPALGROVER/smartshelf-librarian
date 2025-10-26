-- Create enum for user roles
CREATE TYPE public.app_role AS ENUM ('student', 'librarian', 'admin');

-- Create enum for book status
CREATE TYPE public.book_status AS ENUM ('available', 'reserved', 'issued');

-- Create enum for reservation status
CREATE TYPE public.reservation_status AS ENUM ('active', 'completed', 'expired', 'cancelled');

-- Create profiles table
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  student_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create user_roles table (separate for security)
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, role)
);

-- Create shelves table
CREATE TABLE public.shelves (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shelf_number INTEGER NOT NULL UNIQUE,
  current_weight DECIMAL(8,2) DEFAULT 0,
  max_weight DECIMAL(8,2) DEFAULT 5000, -- in grams
  is_active BOOLEAN DEFAULT true,
  last_sensor_update TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create books table
CREATE TABLE public.books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  isbn TEXT,
  shelf_id UUID REFERENCES public.shelves(id) ON DELETE SET NULL,
  status book_status NOT NULL DEFAULT 'available',
  cover_image TEXT,
  description TEXT,
  weight DECIMAL(8,2), -- in grams
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create reservations table
CREATE TABLE public.reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID REFERENCES public.books(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  reserved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  status reservation_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create issued_books table
CREATE TABLE public.issued_books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID REFERENCES public.books(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  due_date TIMESTAMPTZ NOT NULL,
  returned_at TIMESTAMPTZ,
  reservation_id UUID REFERENCES public.reservations(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shelves ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issued_books ENABLE ROW LEVEL SECURITY;

-- Create security definer function to check roles
CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles
    WHERE user_id = _user_id
      AND role = _role
  )
$$;

-- RLS Policies for profiles
CREATE POLICY "Users can view their own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- RLS Policies for user_roles
CREATE POLICY "Users can view their own roles"
  ON public.user_roles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all roles"
  ON public.user_roles FOR SELECT
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can insert roles"
  ON public.user_roles FOR INSERT
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can update roles"
  ON public.user_roles FOR UPDATE
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Admins can delete roles"
  ON public.user_roles FOR DELETE
  USING (public.has_role(auth.uid(), 'admin'));

-- RLS Policies for shelves
CREATE POLICY "Everyone can view shelves"
  ON public.shelves FOR SELECT
  USING (true);

CREATE POLICY "Admins can manage shelves"
  ON public.shelves FOR ALL
  USING (public.has_role(auth.uid(), 'admin'));

-- RLS Policies for books
CREATE POLICY "Everyone can view books"
  ON public.books FOR SELECT
  USING (true);

CREATE POLICY "Admins can manage books"
  ON public.books FOR ALL
  USING (public.has_role(auth.uid(), 'admin'));

-- RLS Policies for reservations
CREATE POLICY "Users can view their own reservations"
  ON public.reservations FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Librarians and admins can view all reservations"
  ON public.reservations FOR SELECT
  USING (public.has_role(auth.uid(), 'librarian') OR public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Students can create reservations"
  ON public.reservations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Students can update their own reservations"
  ON public.reservations FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Librarians can update all reservations"
  ON public.reservations FOR UPDATE
  USING (public.has_role(auth.uid(), 'librarian') OR public.has_role(auth.uid(), 'admin'));

-- RLS Policies for issued_books
CREATE POLICY "Users can view their own issued books"
  ON public.issued_books FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Librarians and admins can view all issued books"
  ON public.issued_books FOR SELECT
  USING (public.has_role(auth.uid(), 'librarian') OR public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Librarians can create issued books"
  ON public.issued_books FOR INSERT
  WITH CHECK (public.has_role(auth.uid(), 'librarian') OR public.has_role(auth.uid(), 'admin'));

CREATE POLICY "Librarians can update issued books"
  ON public.issued_books FOR UPDATE
  USING (public.has_role(auth.uid(), 'librarian') OR public.has_role(auth.uid(), 'admin'));

-- Create function to handle new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Insert into profiles
  INSERT INTO public.profiles (id, email, full_name, student_id)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    NEW.raw_user_meta_data->>'student_id'
  );
  
  -- Assign default role as student
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'student');
  
  RETURN NEW;
END;
$$;

-- Create trigger for new user signup
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Create function to update timestamps
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Create triggers for updated_at
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_shelves_updated_at
  BEFORE UPDATE ON public.shelves
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_books_updated_at
  BEFORE UPDATE ON public.books
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_reservations_updated_at
  BEFORE UPDATE ON public.reservations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_issued_books_updated_at
  BEFORE UPDATE ON public.issued_books
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Enable realtime for sensor updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.shelves;
ALTER PUBLICATION supabase_realtime ADD TABLE public.reservations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.issued_books;

-- Insert initial shelves (2 shelves for prototype)
INSERT INTO public.shelves (shelf_number, max_weight) VALUES (1, 5000);
INSERT INTO public.shelves (shelf_number, max_weight) VALUES (2, 5000);