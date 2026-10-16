create table if not exists users (
  id serial primary key,
  google_sub text unique not null,
  email text not null,
  name text not null,
  picture text,
  phone text,
  role text not null default 'rider',
  rating_sum integer not null default 0,
  rating_count integer not null default 0,
  trips_count integer not null default 0,
  vehicle_type text,
  vehicle_make text,
  vehicle_model text,
  vehicle_color text,
  vehicle_plate text,
  is_online boolean not null default false,
  lat double precision,
  lng double precision,
  location_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists rides (
  id serial primary key,
  passenger_id integer not null references users(id),
  driver_id integer references users(id),
  vehicle_type text not null default 'car',
  pickup_label text not null,
  pickup_lat double precision not null,
  pickup_lng double precision not null,
  dropoff_label text not null,
  dropoff_lat double precision not null,
  dropoff_lng double precision not null,
  distance_km double precision not null,
  offered_fare integer not null,
  accepted_fare integer,
  status text not null default 'open',
  cancelled_by text,
  passenger_rating integer,
  driver_rating integer,
  created_at timestamptz not null default now(),
  matched_at timestamptz,
  arrived_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz
);
create index if not exists rides_passenger_idx on rides (passenger_id);
create index if not exists rides_driver_idx on rides (driver_id);
create index if not exists rides_status_idx on rides (status);

create table if not exists bids (
  id serial primary key,
  ride_id integer not null references rides(id) on delete cascade,
  driver_id integer not null references users(id),
  fare integer not null,
  eta_minutes integer not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  unique (ride_id, driver_id)
);
create index if not exists bids_ride_idx on bids (ride_id);

create table if not exists wallet_tx (
  id serial primary key,
  user_id integer not null references users(id),
  ride_id integer references rides(id),
  amount integer not null,
  kind text not null,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists wallet_user_idx on wallet_tx (user_id);
