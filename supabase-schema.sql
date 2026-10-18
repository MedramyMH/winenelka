-- وين نلقى؟ — Supabase starter schema
-- Run in Supabase SQL Editor. Review policies before production launch.
create extension if not exists pgcrypto;
create type public.account_role as enum ('client','provider','admin');
create type public.availability_status as enum ('available','busy','unavailable');
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 role public.account_role not null default 'client',
 first_name text, last_name text, display_name text,
 avatar_url text, bio text,
 wilaya text, delegation text, sector text,
 latitude double precision, longitude double precision,
 availability public.availability_status not null default 'unavailable',
 is_verified boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.categories (
 id uuid primary key default gen_random_uuid(),
 name_ar text not null, name_fr text, slug text unique not null,
 parent_id uuid references public.categories(id) on delete set null,
 icon text, is_active boolean not null default true, sort_order int not null default 0,
 created_at timestamptz not null default now()
);
create table public.services (
 id uuid primary key default gen_random_uuid(),
 provider_id uuid not null references public.profiles(id) on delete cascade,
 category_id uuid not null references public.categories(id),
 title text not null, description text,
 tasks text[] not null default '{}', physical_requirements text,
 mental_requirements text, experience_years int, price_from numeric(10,3), price_unit text,
 is_active boolean not null default true, created_at timestamptz not null default now()
);
-- Private contact details are deliberately isolated from publicly readable profiles.
create table public.private_contacts (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 phone text, email text, updated_at timestamptz not null default now()
);
create table public.marketplace_listings (
 id uuid primary key default gen_random_uuid(), seller_id uuid not null references public.profiles(id) on delete cascade,
 title text not null, description text not null, price numeric(10,3) not null check(price >= 0),
 category text not null, condition text not null default 'used' check(condition in ('new','used','refurbished')),
 wilaya text, delegation text, sector text, image_urls text[] not null default '{}',
 status text not null default 'active' check(status in ('active','sold','hidden','removed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.provider_media (
 id uuid primary key default gen_random_uuid(), provider_id uuid not null references public.profiles(id) on delete cascade,
 storage_path text not null, caption text, media_type text not null default 'portfolio', created_at timestamptz not null default now()
);
create table public.announcements (
 id uuid primary key default gen_random_uuid(), client_id uuid not null references public.profiles(id) on delete cascade,
 category_id uuid references public.categories(id), title text not null, description text not null,
 wilaya text, delegation text, sector text, status text not null default 'open' check(status in ('open','closed','cancelled')),
 expires_at timestamptz, created_at timestamptz not null default now()
);
create table public.subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 plan_code text not null check(plan_code in ('daily','monthly','yearly')),
 starts_at timestamptz not null default now(), ends_at timestamptz not null,
 status text not null default 'pending' check(status in ('pending','active','expired','cancelled')),
 payment_provider text, provider_reference text, created_at timestamptz not null default now()
);
create table public.payments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 subscription_id uuid references public.subscriptions(id), amount numeric(10,3) not null,
 currency text not null default 'TND', method text not null,
 status text not null default 'pending' check(status in ('pending','succeeded','failed','refunded')),
 provider_reference text, created_at timestamptz not null default now()
);
create table public.reviews (
 id uuid primary key default gen_random_uuid(), service_id uuid not null references public.services(id) on delete cascade,
 client_id uuid not null references public.profiles(id) on delete cascade,
 provider_id uuid not null references public.profiles(id) on delete cascade,
 rating int not null check(rating between 1 and 5), comment text,
 completion_photo_path text, service_completed boolean not null default false,
 created_at timestamptz not null default now(), unique(service_id,client_id)
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null, body text not null, kind text not null default 'general',
 related_id uuid, read_at timestamptz, created_at timestamptz not null default now()
);
create index services_category_idx on public.services(category_id) where is_active;
create index services_provider_idx on public.services(provider_id) where is_active;
create index marketplace_category_idx on public.marketplace_listings(category,status,created_at desc);
create index marketplace_location_idx on public.marketplace_listings(wilaya,delegation,sector) where status = 'active';
create index profiles_location_idx on public.profiles(wilaya,delegation,sector);
create index announcements_category_idx on public.announcements(category_id,status,created_at desc);
create index reviews_provider_idx on public.reviews(provider_id,created_at desc);

-- Enable RLS. Private contact data must never be exposed by public profile reads.
alter table public.profiles enable row level security;
alter table public.private_contacts enable row level security;
alter table public.marketplace_listings enable row level security;
alter table public.categories enable row level security;
alter table public.services enable row level security;
alter table public.provider_media enable row level security;
alter table public.announcements enable row level security;
alter table public.subscriptions enable row level security;
alter table public.payments enable row level security;
alter table public.reviews enable row level security;
alter table public.notifications enable row level security;

create policy "active categories readable" on public.categories for select using (is_active = true);
create policy "public profile basics readable" on public.profiles for select using (true);
create policy "owners read own private contact" on public.private_contacts for select using (auth.uid() = user_id);
create policy "owners insert own private contact" on public.private_contacts for insert with check (auth.uid() = user_id);
create policy "owners update own private contact" on public.private_contacts for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "active marketplace listings readable" on public.marketplace_listings for select using (status = 'active' or auth.uid() = seller_id);
create policy "sellers create own listings" on public.marketplace_listings for insert with check (auth.uid() = seller_id);
create policy "sellers update own listings" on public.marketplace_listings for update using (auth.uid() = seller_id) with check (auth.uid() = seller_id);
create policy "owners manage own profile" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "users create own profile" on public.profiles for insert with check (auth.uid() = id);
create policy "active services readable" on public.services for select using (is_active = true);
create policy "providers manage own services" on public.services for all using (auth.uid() = provider_id) with check (auth.uid() = provider_id);
create policy "public portfolio readable" on public.provider_media for select using (true);
create policy "owners manage own media" on public.provider_media for all using (auth.uid() = provider_id) with check (auth.uid() = provider_id);
create policy "open announcements readable" on public.announcements for select using (status = 'open' or auth.uid() = client_id);
create policy "clients manage own announcements" on public.announcements for all using (auth.uid() = client_id) with check (auth.uid() = client_id);
create policy "users read own subscriptions" on public.subscriptions for select using (auth.uid() = user_id);
create policy "users read own payments" on public.payments for select using (auth.uid() = user_id);
create policy "reviews readable" on public.reviews for select using (true);
create policy "clients create own reviews" on public.reviews for insert with check (auth.uid() = client_id and service_completed = true);
create policy "users read own notifications" on public.notifications for select using (auth.uid() = user_id);
create policy "users update own notifications" on public.notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- IMPORTANT PRODUCTION TODO:
-- 1) Keep phone/email in private_contacts. Reveal them only through a server-side Edge Function after checking active subscription; do not expose the table through a public view.
-- 2) Add admin-only policies/claims for category moderation and provider verification.
-- 3) Create an Edge Function to verify payment provider callbacks; never trust client-side payment success.
-- 4) Review review eligibility using an order/booking completion record; do not trust a client boolean alone.
-- 5) Add rate limits, anti-spam controls, audit logs, and verified identity/consent workflows.
