-- ============================================================================
-- Invoice-ready support  —  run once in Supabase → SQL Editor
-- ============================================================================
-- Adds the fields that let a finished job be turned into a QuickBooks invoice:
-- which quote to bill from, when the job was finished, and what came back from
-- QuickBooks afterwards. Nothing existing is changed or removed.
--
-- Safe to run twice: every statement is "if not exists".
-- The admin works before you run this — the job list steps back through a
-- shorter column list when these are missing — so there is no rush, and no
-- window where the page is broken.

-- ── 1. Job: which quote, and what QuickBooks said ───────────────────────────
-- invoice_quote_id is a UUID because that is what tce_quotes.id is. The first
-- version of this file said bigint and Postgres refused the whole script:
--   foreign key constraint ... cannot be implemented
--   Key columns "invoice_quote_id" and "id" are of incompatible types:
--   bigint and uuid
-- Worth knowing that the error is the good outcome: the database would not let
-- a broken link be created. Nothing was applied, because the ALTER is one
-- statement and either all of it lands or none of it does.
alter table tce_jobs
  add column if not exists invoice_quote_id    uuid references tce_quotes(id),
  add column if not exists completed_at        timestamptz,
  add column if not exists qbo_invoice_id      text,
  add column if not exists qbo_invoice_number  text,
  add column if not exists invoiced_at         timestamptz,
  add column if not exists invoice_note        text;

comment on column tce_jobs.invoice_quote_id is
  'The saved quote this job is billed from. A job collects several quotes as it
   changes; this records which one was chosen, rather than leaving it to
   whoever is typing the invoice to guess at the newest.';
comment on column tce_jobs.completed_at is
  'When the job was marked ready to invoice — the end of the work, not the
   invoice date.';
comment on column tce_jobs.qbo_invoice_number is
  'The human invoice number, e.g. 1042. What you search for when the customer
   rings about it.';

-- ── 1b. The other end of the job: the estimate ─────────────────────────────
-- Same shape as the invoice fields, for the quote that goes out BEFORE the
-- work. A job collects revisions, and which one was actually sent to the
-- customer is not something to reconstruct from dates afterwards.
alter table tce_jobs
  add column if not exists estimate_quote_id    uuid references tce_quotes(id),
  add column if not exists qbo_estimate_id      text,
  add column if not exists qbo_estimate_number  text,
  add column if not exists estimated_at         timestamptz;

comment on column tce_jobs.estimate_quote_id is
  'The saved quote sent to the customer as the estimate. When they approve it,
   the same quote is normally the one marked to invoice.';

-- Finding the jobs waiting to be billed is the one query this table will be
-- asked constantly, so it gets an index.
create index if not exists tce_jobs_ready_to_invoice
  on tce_jobs (status) where status = 'ready_to_invoice';

-- ── 2. Customer → QuickBooks ────────────────────────────────────────────────
-- Your customer names and QuickBooks' are not always the same string, and an
-- invoice raised against a name QuickBooks has never heard of creates a new
-- customer rather than failing — which is worse, because it looks like it
-- worked. This table is the link, keyed on the name as it appears in the admin.
create table if not exists tce_customer_map (
  customer_name     text primary key,
  qbo_customer_id   text,
  qbo_display_name  text,
  updated_at        timestamptz not null default now()
);

comment on table tce_customer_map is
  'Maps a TCE customer name to its QuickBooks customer. Filled in by Claude;
   the admin only shows a "QB ✓" against a name that has a link.';

-- ── 3. Row-level security ───────────────────────────────────────────────────
-- Same rule as the rest of the system: signed in means you can read and write.
-- tce_jobs already has its policies; this is only for the new table.
alter table tce_customer_map enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies
                 where tablename='tce_customer_map' and policyname='signed in can read customer map') then
    create policy "signed in can read customer map"
      on tce_customer_map for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies
                 where tablename='tce_customer_map' and policyname='signed in can write customer map') then
    create policy "signed in can write customer map"
      on tce_customer_map for all to authenticated using (true) with check (true);
  end if;
end $$;

-- ── 4a. Did the link actually get made? ─────────────────────────────────────
-- The foreign key is the part that went wrong first time. This reports whether
-- it exists, rather than leaving you to assume it does.
select 'invoice_quote_id' as col,
       case when exists (select 1 from information_schema.table_constraints
                          where constraint_name='tce_jobs_invoice_quote_id_fkey'
                            and table_name='tce_jobs')
            then 'linked to tce_quotes ✓' else 'NO LINK' end as fk_status
union all
select 'estimate_quote_id',
       case when exists (select 1 from information_schema.table_constraints
                          where constraint_name='tce_jobs_estimate_quote_id_fkey'
                            and table_name='tce_jobs')
            then 'linked to tce_quotes ✓' else 'NO LINK' end;

-- ── 4. Check it worked ──────────────────────────────────────────────────────
-- Run this after the above; it should list all ten new job columns and the
-- three map columns — thirteen rows.
select 'tce_jobs' as tbl, column_name
  from information_schema.columns
 where table_name='tce_jobs'
   and column_name in ('invoice_quote_id','completed_at','qbo_invoice_id',
                       'qbo_invoice_number','invoiced_at','invoice_note',
                       'estimate_quote_id','qbo_estimate_id',
                       'qbo_estimate_number','estimated_at')
union all
select 'tce_customer_map', column_name
  from information_schema.columns
 where table_name='tce_customer_map'
   and column_name in ('customer_name','qbo_customer_id','qbo_display_name')
 order by 1,2;
