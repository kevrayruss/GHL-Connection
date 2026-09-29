-- Drive refused these moves with a per-minute quota 403 (nothing moved); clear the error so they retry.
update public.shared_intake_files set move_error = null
 where scan_id = '068b68d4-88ac-4ad8-8416-6146caa02c35' and moved_at is null and move_error like 'HTTP 403%Quota exceeded%';
