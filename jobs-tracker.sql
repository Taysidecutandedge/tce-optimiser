-- ============================================================================
-- Jobs tracker support  —  run once in Supabase → SQL Editor
-- ============================================================================
-- Adds the three moments between "estimate sent" and "on the saw" that the job
-- list could not record before: the customer said yes, the materials were
-- ordered, the materials arrived. Used by tce-jobs.html.
--
-- Nothing existing is changed or removed, and the job statuses the admin page
-- uses are left exactly as they are: these are dates stamped alongside the
-- status, not new statuses, so the admin keeps working untouched.
--
-- Safe to run twice: every statement is "if not exists".
-- tce-jobs.html still opens before you run this; it just can't save the new
-- steps until you do, and says so.

alter table tce_jobs
  add column if not exists approved_at            timestamptz,
  add column if not exists approved_via           text,
  add column if not exists materials_ordered_at   timestamptz,
  add column if not exists materials_delivered_at timestamptz,
  add column if not exists order_note             text;

comment on column tce_jobs.approved_at is
  'When the customer approved the estimate — whether they pressed Approve in
   QuickBooks or said yes by message or phone.';
comment on column tce_jobs.approved_via is
  'How the approval came in: quickbooks (customer pressed Approve, picked up by
   Claude''s check) or manual (Rob tapped Mark approved).';
comment on column tce_jobs.materials_ordered_at is
  'When the boards and edging for this job were ordered from the supplier.';
comment on column tce_jobs.materials_delivered_at is
  'When the materials arrived and the job could go on the saw.';
comment on column tce_jobs.order_note is
  'Free text about the order: supplier, Lathams order ref, anything odd.';

-- Approved-but-not-ordered is the list that matters most, so it gets an index.
create index if not exists tce_jobs_approved_not_ordered
  on tce_jobs (approved_at) where approved_at is not null and materials_ordered_at is null;

-- ── Added 14 Nov 2026: declined estimates ──────────────────────────────────
alter table tce_jobs
  add column if not exists declined_at     timestamptz,
  add column if not exists declined_reason text;

comment on column tce_jobs.declined_at is
  'When the customer turned the estimate down (Decline in QuickBooks, or Rob
   tapped Declined). Cleared again if the job is reopened.';
comment on column tce_jobs.declined_reason is
  'Price / Went elsewhere / Job cancelled / No reply, plus an optional note.';

-- ── Added 14 Nov 2026: which quote the materials were ordered from ──────────
-- So a change made in the optimiser after ordering shows as "order 1 more sheet"
-- instead of going unnoticed.
alter table tce_jobs
  add column if not exists materials_quote_id uuid references tce_quotes(id);
