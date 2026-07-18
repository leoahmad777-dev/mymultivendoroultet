-- ====================================================================================
-- PROJECT: MULTI VENDOR SALES TRACKING SYSTEM (PWA)
-- PHASE: 5 - BACKEND & DATABASE SETUP (SUPABASE / POSTGRESQL)
-- AUTHOR: SENIOR BACKEND TEAM
-- ====================================================================================

-- 1. EXTENSIONS & CUSTOM TYPES (ENUMS)
-- ====================================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";-- ====================================================================================
-- PROJECT: MULTI VENDOR SALES TRACKING SYSTEM (PWA)
-- PHASE: 5 - BACKEND & DATABASE SETUP (SUPABASE / POSTGRESQL)
-- AUTHOR: SENIOR BACKEND TEAM
-- ====================================================================================

-- 1. EXTENSIONS & CUSTOM TYPES (ENUMS)
-- ====================================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE user_role AS ENUM ('admin', 'supervisor', 'cashier', 'vendor');
CREATE TYPE record_status AS ENUM ('active', 'inactive', 'deleted');
CREATE TYPE event_status AS ENUM ('draft', 'ongoing', 'completed');
CREATE TYPE commission_type AS ENUM ('percentage', 'flat');
CREATE TYPE stock_movement_type AS ENUM ('in', 'out', 'adjustment', 'void_return', 'sale');
CREATE TYPE transaction_status AS ENUM ('completed', 'voided', 'refunded');
CREATE TYPE payment_method AS ENUM ('cash', 'qr_pay', 'mixed');
CREATE TYPE settlement_status AS ENUM ('pending', 'processing', 'paid');

-- 2. TABLE DEFINITIONS
-- ====================================================================================

-- USERS (Extends Supabase auth.users)
CREATE TABLE public.users (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    role user_role DEFAULT 'vendor'::user_role NOT NULL,
    status record_status DEFAULT 'active'::record_status NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- EVENTS
CREATE TABLE public.events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,
    location VARCHAR(255),
    status event_status DEFAULT 'draft'::event_status NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- VENDORS
CREATE TABLE public.vendors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.users(id) ON DELETE RESTRICT,
    business_name VARCHAR(255) NOT NULL,
    ssm_number VARCHAR(100),
    bank_name VARCHAR(100),
    bank_account VARCHAR(100),
    qr_payment_url TEXT,
    commission_type commission_type DEFAULT 'percentage'::commission_type NOT NULL,
    commission_rate NUMERIC(10,2) DEFAULT 0.00 NOT NULL,
    status record_status DEFAULT 'active'::record_status NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- CATEGORIES
CREATE TABLE public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    color_code VARCHAR(20) DEFAULT '#f4f4f5',
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- PRODUCTS
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE CASCADE NOT NULL,
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(100) UNIQUE,
    price NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    cost NUMERIC(10,2) DEFAULT 0.00 CHECK (cost >= 0),
    stock INTEGER DEFAULT 0 NOT NULL,
    photo_url TEXT,
    status record_status DEFAULT 'active'::record_status NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- TRANSACTIONS (Master Receipt)
CREATE TABLE public.transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID REFERENCES public.events(id) ON DELETE RESTRICT NOT NULL,
    cashier_id UUID REFERENCES public.users(id) ON DELETE RESTRICT NOT NULL,
    receipt_no VARCHAR(50) UNIQUE NOT NULL,
    total_amount NUMERIC(10,2) NOT NULL CHECK (total_amount >= 0),
    status transaction_status DEFAULT 'completed'::transaction_status NOT NULL,
    approved_by UUID REFERENCES public.users(id) ON DELETE RESTRICT, -- For Voiding
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- TRANSACTION ITEMS (Line Items / Vendor Breakdown)
CREATE TABLE public.transaction_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID REFERENCES public.transactions(id) ON DELETE CASCADE NOT NULL,
    product_id UUID REFERENCES public.products(id) ON DELETE RESTRICT NOT NULL,
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE RESTRICT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal NUMERIC(10,2) NOT NULL CHECK (subtotal >= 0),
    commission_amount NUMERIC(10,2) NOT NULL CHECK (commission_amount >= 0),
    net_vendor_amount NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- PAYMENTS
CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID REFERENCES public.transactions(id) ON DELETE CASCADE NOT NULL,
    method payment_method NOT NULL,
    amount NUMERIC(10,2) NOT NULL CHECK (amount >= 0),
    reference_no VARCHAR(255),
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- STOCK MOVEMENTS (Audit Trail for Inventory)
CREATE TABLE public.stock_movements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
    type stock_movement_type NOT NULL,
    quantity INTEGER NOT NULL,
    reason VARCHAR(255),
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- SETTLEMENTS (Payout to Vendors)
CREATE TABLE public.settlements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id UUID REFERENCES public.events(id) ON DELETE RESTRICT NOT NULL,
    vendor_id UUID REFERENCES public.vendors(id) ON DELETE RESTRICT NOT NULL,
    total_gross_sales NUMERIC(10,2) NOT NULL,
    total_commission NUMERIC(10,2) NOT NULL,
    net_payout NUMERIC(10,2) NOT NULL,
    status settlement_status DEFAULT 'pending'::settlement_status NOT NULL,
    paid_at TIMESTAMPTZ,
    payment_proof_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);


-- 3. HELPER FUNCTIONS FOR ROW LEVEL SECURITY (RLS)
-- ====================================================================================
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS user_role AS $$
  SELECT role FROM public.users WHERE id = auth.uid() LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER;


-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ====================================================================================
-- Enable RLS on all tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

-- USERS Table Policy
CREATE POLICY "Users can view their own profile, Admins view all" ON public.users
    FOR SELECT USING (auth.uid() = id OR public.get_user_role() IN ('admin', 'supervisor'));

-- PRODUCTS Table Policy
CREATE POLICY "Everyone can view active products, Admins manage all, Vendors manage own" ON public.products
    FOR ALL USING (
        public.get_user_role() IN ('admin', 'supervisor') 
        OR (public.get_user_role() = 'vendor' AND vendor_id IN (SELECT id FROM public.vendors WHERE user_id = auth.uid()))
        OR (public.get_user_role() = 'cashier' AND status = 'active')
    );

-- TRANSACTIONS Table Policy
CREATE POLICY "Cashier insert, Admin/Supervisor manage, Vendor cannot view master receipt" ON public.transactions
    FOR ALL USING (
        public.get_user_role() IN ('admin', 'supervisor')
        OR (public.get_user_role() = 'cashier' AND cashier_id = auth.uid())
    );

-- TRANSACTION ITEMS Policy (Crucial for Vendor Privacy)
CREATE POLICY "Vendor view own sales only, Admin view all, Cashier insert" ON public.transaction_items
    FOR SELECT USING (
        public.get_user_role() IN ('admin', 'supervisor')
        OR (public.get_user_role() = 'vendor' AND vendor_id IN (SELECT id FROM public.vendors WHERE user_id = auth.uid()))
        OR public.get_user_role() = 'cashier'
    );
CREATE POLICY "Cashiers and Admins can insert items" ON public.transaction_items
    FOR INSERT WITH CHECK (public.get_user_role() IN ('admin', 'cashier'));

-- SETTLEMENTS Policy
CREATE POLICY "Vendor view own settlements, Admin manage all" ON public.settlements
    FOR SELECT USING (
        public.get_user_role() IN ('admin', 'supervisor')
        OR (public.get_user_role() = 'vendor' AND vendor_id IN (SELECT id FROM public.vendors WHERE user_id = auth.uid()))
    );


-- 5. AUTOMATION TRIGGERS & RPC (STORED PROCEDURES)
-- ====================================================================================

-- Trigger to auto-create user profile on Supabase Auth Signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', COALESCE((new.raw_user_meta_data->>'role')::user_role, 'vendor'::user_role));
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- RPC (Remote Procedure Call) for Secure Checkout Process
-- This function handles the entire checkout atomically. If one item fails (e.g. out of stock), the whole transaction rolls back.
CREATE OR REPLACE FUNCTION public.process_checkout_v1(
    p_event_id UUID,
    p_cashier_id UUID,
    p_total_amount NUMERIC,
    p_payment_method payment_method,
    p_payment_amount NUMERIC,
    p_items JSONB -- Array of items: [{product_id, vendor_id, qty, unit_price, commission, net_amount}]
)
RETURNS JSONB AS $$
DECLARE
    v_transaction_id UUID;
    v_receipt_no VARCHAR;
    v_item RECORD;
    v_current_stock INTEGER;
BEGIN
    -- 1. Generate Receipt No (Format: EVT-YYYYMMDD-XXXX)
    v_receipt_no := 'EVT-' || to_char(NOW(), 'YYYYMMDD') || '-' || upper(substring(md5(random()::text) from 1 for 4));

    -- 2. Insert Master Transaction
    INSERT INTO public.transactions (event_id, cashier_id, receipt_no, total_amount, status)
    VALUES (p_event_id, p_cashier_id, v_receipt_no, p_total_amount, 'completed')
    RETURNING id INTO v_transaction_id;

    -- 3. Insert Payment
    INSERT INTO public.payments (transaction_id, method, amount)
    VALUES (v_transaction_id, p_payment_method, p_payment_amount);

    -- 4. Loop through items, check stock, insert items, update stock
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id UUID, vendor_id UUID, quantity INTEGER, unit_price NUMERIC, commission_amount NUMERIC, net_vendor_amount NUMERIC)
    LOOP
        -- Lock the row for update to prevent concurrency issues (overselling)
        SELECT stock INTO v_current_stock FROM public.products WHERE id = v_item.product_id FOR UPDATE;

        IF v_current_stock < v_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for product ID: %', v_item.product_id;
        END IF;

        -- Deduct stock
        UPDATE public.products SET stock = stock - v_item.quantity WHERE id = v_item.product_id;

        -- Insert Line Item
        INSERT INTO public.transaction_items (transaction_id, product_id, vendor_id, quantity, unit_price, subtotal, commission_amount, net_vendor_amount)
        VALUES (v_transaction_id, v_item.product_id, v_item.vendor_id, v_item.quantity, v_item.unit_price, (v_item.quantity * v_item.unit_price), v_item.commission_amount, v_item.net_vendor_amount);
        
        -- Insert Stock Movement Audit
        INSERT INTO public.stock_movements (product_id, type, quantity, reason, created_by)
        VALUES (v_item.product_id, 'sale', v_item.quantity, 'POS Sale: ' || v_receipt_no, p_cashier_id);
    END LOOP;

    -- Return success payload
    RETURN jsonb_build_object('success', true, 'transaction_id', v_transaction_id, 'receipt_no', v_receipt_no);
EXCEPTION
    WHEN OTHERS THEN
        -- PostgreSQL automatically rolls back the transaction on exception
        RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ====================================================================================
-- END OF SCRIPT
-- ====================================================================================