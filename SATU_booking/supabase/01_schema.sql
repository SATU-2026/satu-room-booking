-- SATU Booking v1. Run once in a NEW Supabase project using SQL Editor.
-- All public-client access goes through explicitly granted RPC functions.
-- No existing calendar tables are modified. No production bookings are seeded.
begin;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;
set search_path=public,extensions;
create table public.bkg_campuses (
 id text primary key, name text not null, short text not null,
 contact_name text not null, contact_phone text not null
);
create table public.bkg_rooms (
 id text primary key default gen_random_uuid()::text,
 campus_id text not null references public.bkg_campuses(id),
 name text not null check(length(trim(name)) between 1 and 200),
 capacity integer check(capacity between 1 and 100000),
 active boolean not null default true, is_sample boolean not null default false,
 unique(id,campus_id)
);
create table public.bkg_scopes (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 name text not null default '', campus_id text references public.bkg_campuses(id),
 role text not null check(role in ('staff','head','admin')),
 check((role='admin' and campus_id is null) or (role<>'admin' and campus_id is not null))
);
create unique index bkg_scope_unique on public.bkg_scopes(user_id,coalesce(campus_id,'*'));
create table public.bkg_bookings (
 id uuid primary key default gen_random_uuid(), reference text not null unique default 'BK-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
 kind text not null default 'booking' check(kind in ('booking','block')),
 room_id text not null, campus_id text not null,
 starts_at timestamptz not null, ends_at timestamptz not null,
 status text not null default 'pending' check(status in ('pending','reviewed','approved','rejected','cancelled','blocked')),
 fullname text check(length(fullname)<=200), student_id text check(length(student_id)<=20), phone text check(phone~'^0[0-9]{8,9}$'),
 faculty text check(length(faculty)<=200), group_name text check(length(group_name)<=200), detail text check(length(detail)<=4000),
 participants integer check(participants between 1 and 100000), reason text not null default '' check(length(reason)<=2000),
 token_hash text, idempotency_key uuid unique, created_at timestamptz not null default now(),
 foreign key(room_id,campus_id) references public.bkg_rooms(id,campus_id),
 check(ends_at>starts_at),
 check(kind='block' or (fullname is not null and student_id is not null and phone is not null and faculty is not null and group_name is not null and detail is not null and participants is not null and token_hash is not null)),
 constraint bkg_no_overlap exclude using gist (room_id with =,tstzrange(starts_at,ends_at,'[)') with &&)
 where(status in ('pending','reviewed','approved','blocked'))
);
create index bkg_calendar_idx on public.bkg_bookings(campus_id,starts_at);
create index bkg_phone_idx on public.bkg_bookings(phone,created_at desc);
create table public.bkg_history (
 id bigint generated always as identity primary key, booking_id uuid not null references public.bkg_bookings(id),
 at timestamptz not null default now(), actor text not null, actor_id uuid, action text not null, reason text not null default ''
);
create index bkg_history_booking_idx on public.bkg_history(booking_id,id);
create table public.bkg_attachments (
 id uuid primary key default gen_random_uuid(), booking_id uuid not null references public.bkg_bookings(id),
 name text not null, path text not null unique, size bigint not null check(size between 1 and 5242880),
 mime text not null check(mime in ('application/pdf','image/jpeg','image/png')), created_at timestamptz not null default now()
);
create index bkg_files_booking_idx on public.bkg_attachments(booking_id);
create table public.bkg_rate_limits (bucket text primary key,window_at timestamptz not null,hits integer not null);
-- Defense in depth: no direct data access from browser roles, including catalog data.
alter table public.bkg_campuses enable row level security;
alter table public.bkg_rooms enable row level security;
alter table public.bkg_scopes enable row level security;
alter table public.bkg_bookings enable row level security;
alter table public.bkg_history enable row level security;
alter table public.bkg_attachments enable row level security;
alter table public.bkg_rate_limits enable row level security;
revoke all on public.bkg_campuses,public.bkg_rooms,public.bkg_scopes,public.bkg_bookings,public.bkg_history,public.bkg_attachments,public.bkg_rate_limits from anon,authenticated;
grant all on public.bkg_campuses,public.bkg_rooms,public.bkg_scopes,public.bkg_bookings,public.bkg_history,public.bkg_attachments,public.bkg_rate_limits to service_role;
grant usage,select on sequence public.bkg_history_id_seq to service_role;

create function public.bkg_has_scope(p_campus text,p_roles text[] default array['staff','head','admin']) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.bkg_scopes s where s.user_id=auth.uid() and s.role=any(p_roles) and (s.role='admin' or s.campus_id=p_campus));
$$;
create function public.bkg_allowed(p_id uuid,p_token text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.bkg_bookings b where b.id=p_id and
 (case when p_token is not null then length(p_token)>=32 and b.token_hash=encode(extensions.digest(p_token,'sha256'),'hex')
 else public.bkg_has_scope(b.campus_id) end));
$$;
create function public.bkg_audit(p_id uuid,p_action text,p_reason text default '',p_customer boolean default false) returns void
language plpgsql security definer set search_path='' as $$
 begin
 insert into public.bkg_history(booking_id,actor,actor_id,action,reason)
 values(p_id,case when p_customer then 'ผู้จอง' else coalesce((select nullif(s.name,'') from public.bkg_scopes s where s.user_id=auth.uid() order by s.name limit 1),'เจ้าหน้าที่') end,
 case when p_customer then null else auth.uid() end,p_action,coalesce(p_reason,''));
 end;
$$;
create function public.bkg_rate(p_action text,p_limit integer) returns void
language plpgsql security definer set search_path='' as $$
 declare h jsonb:=coalesce(nullif(current_setting('request.headers',true),'')::jsonb,'{}'); k text; n integer;
 begin
 k:=p_action||':'||coalesce(nullif(split_part(h->>'x-forwarded-for',',',1),''),auth.uid()::text,'shared');
 insert into public.bkg_rate_limits(bucket,window_at,hits) values(k,date_trunc('minute',now()),1)
 on conflict(bucket) do update set window_at=excluded.window_at,hits=case when bkg_rate_limits.window_at=excluded.window_at then bkg_rate_limits.hits+1 else 1 end returning hits into n;
 if n>p_limit then raise exception 'ทำรายการถี่เกินไป กรุณารอสักครู่แล้วลองใหม่'; end if;
 delete from public.bkg_rate_limits where window_at<now()-interval '1 day';
 end;
$$;
create function public.bkg_meta() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('campuses',(select coalesce(jsonb_agg(to_jsonb(c) order by c.id),'[]') from public.bkg_campuses c),'rooms',(select coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]') from public.bkg_rooms r),'settings',jsonb_build_object('advance_days',5,'cancel_hours',1,'approval','staff_then_head'));
$$;
create function public.bkg_my_scopes() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(s)-'id'),'[]') from public.bkg_scopes s where user_id=auth.uid();
$$;
create function public.bkg_calendar(p_campus text,p_start timestamptz,p_end timestamptz) returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if p_end<=p_start or p_end-p_start>interval '93 days' then raise exception 'ช่วงวันที่ไม่ถูกต้อง'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'reference',b.reference,'room_id',b.room_id,'campus_id',b.campus_id,'starts_at',b.starts_at,'ends_at',b.ends_at,'status',b.status,'kind',b.kind) order by b.starts_at),'[]') from public.bkg_bookings b where b.campus_id=p_campus and b.starts_at<p_end and b.ends_at>p_start and b.status in ('pending','reviewed','approved','blocked'));
 end;
$$;
create function public.bkg_lookup(p_phone text) returns jsonb language plpgsql security definer set search_path='' as $$
 begin
 perform public.bkg_rate('lookup',30);
 if length(trim(p_phone))<8 or length(trim(p_phone))>20 then raise exception 'กรุณากรอกเบอร์โทรหรือเลขทะเบียนให้ถูกต้อง'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'reference',b.reference,'room_id',b.room_id,'campus_id',b.campus_id,'starts_at',b.starts_at,'ends_at',b.ends_at,'status',b.status,'kind',b.kind) order by b.created_at desc),'[]') from public.bkg_bookings b where (b.phone=p_phone or b.student_id=p_phone) and b.kind='booking');
 end;
$$;
create function public.bkg_create(p_data jsonb,p_key uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
 declare r public.bkg_rooms; b public.bkg_bookings; s timestamptz; e timestamptz; n integer; k text;
 begin
 if p_key is null or p_token is null or p_token!~'^[a-f0-9]{48}$' then raise exception 'รหัสส่งคำขอไม่ถูกต้อง'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 select * into b from public.bkg_bookings where idempotency_key=p_key;
 if found then
  if b.token_hash<>encode(extensions.digest(p_token,'sha256'),'hex') then raise exception 'รหัสส่งคำขอไม่ตรงกัน'; end if;
  return jsonb_build_object('id',b.id,'reference',b.reference,'room_id',b.room_id,'campus_id',b.campus_id,'starts_at',b.starts_at,'ends_at',b.ends_at,'status',b.status);
 end if;
 perform public.bkg_rate('create',10);
 foreach k in array array['fullname','student_id','phone','faculty','group_name','detail','room_id'] loop
  if coalesce(length(trim(p_data->>k)),0)=0 then raise exception 'กรุณากรอกข้อมูลที่จำเป็นให้ครบ'; end if;
 end loop;
 if (p_data->>'phone')!~'^0[0-9]{8,9}$' then raise exception 'เบอร์โทรไม่ถูกต้อง'; end if;
 s:=(p_data->>'starts_at')::timestamptz; e:=(p_data->>'ends_at')::timestamptz; n:=(p_data->>'participants')::integer;
 if s is null or e is null or e<=s or not isfinite(s) or not isfinite(e) or (s at time zone 'Asia/Bangkok')::date<>(e at time zone 'Asia/Bangkok')::date then raise exception 'เวลาเริ่มและสิ้นสุดไม่ถูกต้อง ต้องอยู่วันเดียวกัน'; end if;
 if (s at time zone 'Asia/Bangkok')::date<(now() at time zone 'Asia/Bangkok')::date+5 then raise exception 'กรุณาจองล่วงหน้าอย่างน้อย 5 วัน'; end if;
 if n is null or n<1 or n>100000 then raise exception 'จำนวนผู้เข้าร่วมไม่ถูกต้อง'; end if;
 select * into r from public.bkg_rooms where id=p_data->>'room_id' for share;
 if not found or not r.active then raise exception 'ห้องนี้ไม่เปิดรับจอง'; end if;
 insert into public.bkg_bookings(room_id,campus_id,starts_at,ends_at,fullname,student_id,phone,faculty,group_name,detail,participants,token_hash,idempotency_key)
 values(r.id,r.campus_id,s,e,trim(p_data->>'fullname'),trim(p_data->>'student_id'),p_data->>'phone',trim(p_data->>'faculty'),trim(p_data->>'group_name'),trim(p_data->>'detail'),n,encode(extensions.digest(p_token,'sha256'),'hex'),p_key) returning * into b;
 perform public.bkg_audit(b.id,'ส่งคำขอและกันห้อง','',true);
 return jsonb_build_object('id',b.id,'reference',b.reference,'room_id',b.room_id,'campus_id',b.campus_id,'starts_at',b.starts_at,'ends_at',b.ends_at,'status',b.status);
 exception when exclusion_violation then raise exception 'ห้องไม่ว่างในช่วงเวลานี้ กรุณาเลือกเวลาใหม่';
 end;
$$;
create function public.bkg_detail(p_id uuid,p_token text default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
 declare b public.bkg_bookings;
 begin
 if not public.bkg_allowed(p_id,p_token) then raise exception 'ไม่พบรายการหรือรหัสไม่ถูกต้อง / ไม่มีสิทธิ์'; end if;
 select * into b from public.bkg_bookings where id=p_id;
 return (to_jsonb(b)-'token_hash'-'idempotency_key')||jsonb_build_object('history',(select coalesce(jsonb_agg(to_jsonb(h)-'id'-'actor_id'-'booking_id' order by h.id),'[]') from public.bkg_history h where h.booking_id=p_id));
 end;
$$;
create function public.bkg_edit(p_id uuid,p_token text,p_detail text,p_participants integer) returns boolean language plpgsql security definer set search_path='' as $$
 declare b public.bkg_bookings;
 begin
 select * into b from public.bkg_bookings where id=p_id for update;
 if p_token is null or not public.bkg_allowed(p_id,p_token) then raise exception 'รหัสจัดการคำขอไม่ถูกต้อง'; end if;
 if b.status not in ('pending','reviewed','approved') or b.starts_at<=now() then raise exception 'รายการนี้ไม่สามารถแก้ไขได้แล้ว'; end if;
 if p_detail is null or length(trim(p_detail))=0 or length(p_detail)>4000 or p_participants is null or p_participants not between 1 and 100000 then raise exception 'รายละเอียดหรือจำนวนผู้เข้าร่วมไม่ถูกต้อง'; end if;
 update public.bkg_bookings set detail=trim(p_detail),participants=p_participants,status='pending',reason='' where id=p_id;
 perform public.bkg_audit(p_id,'แก้รายละเอียด — ส่งกลับรอตรวจสอบ','',true);return true;
 end;
$$;
create function public.bkg_cancel(p_id uuid,p_token text,p_reason text) returns boolean language plpgsql security definer set search_path='' as $$
 declare b public.bkg_bookings;
 begin
 select * into b from public.bkg_bookings where id=p_id for update;
 if p_token is null or not public.bkg_allowed(p_id,p_token) then raise exception 'รหัสจัดการคำขอไม่ถูกต้อง'; end if;
 if b.status not in ('pending','reviewed','approved') or b.starts_at<now()+interval '1 hour' then raise exception 'เลยกำหนดยกเลิกเองแล้ว กรุณาติดต่อเจ้าหน้าที่'; end if;
 if coalesce(length(trim(p_reason)),0)=0 or length(p_reason)>2000 then raise exception 'กรุณาระบุเหตุผลไม่เกิน 2000 ตัวอักษร'; end if;
 update public.bkg_bookings set status='cancelled',reason=trim(p_reason) where id=p_id;
 perform public.bkg_audit(p_id,'ยกเลิกโดยผู้จอง',trim(p_reason),true);return true;
 end;
$$;
create function public.bkg_staff_list(p_campus text) returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if not public.bkg_has_scope(p_campus) then raise exception 'ไม่มีสิทธิ์จัดการศูนย์นี้'; end if;
 return(select coalesce(jsonb_agg(to_jsonb(b)-'token_hash'-'idempotency_key' order by created_at),'[]') from public.bkg_bookings b where campus_id=p_campus);
 end;
$$;
create function public.bkg_action(p_id uuid,p_action text,p_reason text default '') returns boolean language plpgsql security definer set search_path='' as $$
 declare b public.bkg_bookings; target text; label text;
 begin
 select * into b from public.bkg_bookings where id=p_id for update;
 if not found or not public.bkg_has_scope(b.campus_id) then raise exception 'ไม่มีสิทธิ์จัดการรายการนี้'; end if;
 if p_action='review' and b.status='pending' and public.bkg_has_scope(b.campus_id,array['staff','admin']) then target:='reviewed';label:='ตรวจสอบผ่าน';
 elsif p_action='approve' and b.status='reviewed' and public.bkg_has_scope(b.campus_id,array['head','admin']) then target:='approved';label:='อนุมัติ';
 elsif p_action='reject' and b.status in ('pending','reviewed') then target:='rejected';label:='ไม่อนุมัติ';
 elsif p_action='cancel' and b.status in ('pending','reviewed','approved','blocked') then target:='cancelled';label:='ยกเลิกโดยเจ้าหน้าที่';
 else raise exception 'ไม่มีสิทธิ์ทำขั้นตอนนี้ หรือสถานะเปลี่ยนแล้ว กรุณาโหลดใหม่'; end if;
 if p_action in ('reject','cancel') and coalesce(length(trim(p_reason)),0)=0 then raise exception 'กรุณาระบุเหตุผล'; end if;
 update public.bkg_bookings set status=target,reason=coalesce(trim(p_reason),'') where id=p_id;
 perform public.bkg_audit(p_id,label,p_reason);return true;
 end;
$$;
create function public.bkg_block(p_data jsonb) returns boolean language plpgsql security definer set search_path='' as $$
 declare r public.bkg_rooms; s timestamptz:=(p_data->>'starts_at')::timestamptz; e timestamptz:=(p_data->>'ends_at')::timestamptz; conflicts text; bid uuid;
 begin
 select * into r from public.bkg_rooms where id=p_data->>'room_id';
 if not found or not public.bkg_has_scope(r.campus_id,array['staff','admin']) then raise exception 'ไม่มีสิทธิ์ปิดห้องของศูนย์นี้'; end if;
 if s is null or e is null or not isfinite(s) or not isfinite(e) or s<now() or e<=s or coalesce(length(trim(p_data->>'reason')),0)=0 then raise exception 'ระบุช่วงเวลาในอนาคตและเหตุผลให้ครบ'; end if;
 select string_agg(reference,', ') into conflicts from public.bkg_bookings where room_id=r.id and status in ('pending','reviewed','approved','blocked') and starts_at<e and ends_at>s;
 if conflicts is not null then raise exception 'ปิดห้องไม่ได้ มีรายการชน % กรุณาจัดการรายการเดิมก่อน',conflicts; end if;
 insert into public.bkg_bookings(kind,room_id,campus_id,starts_at,ends_at,status,reason) values('block',r.id,r.campus_id,s,e,'blocked',trim(p_data->>'reason')) returning id into bid;
 perform public.bkg_audit(bid,'ปิดห้องเฉพาะช่วง',p_data->>'reason');return true;
 exception when exclusion_violation then raise exception 'มีรายการจองใหม่ชนช่วงปิดห้อง กรุณาโหลดรายการและตรวจสอบอีกครั้ง';
 end;
$$;
create function public.bkg_save_room(p_data jsonb) returns boolean language plpgsql security definer set search_path='' as $$
 declare rid text:=coalesce(nullif(p_data->>'id',''),gen_random_uuid()::text); oldcampus text;
 begin
 if not public.bkg_has_scope(null,array['admin']) then raise exception 'สำหรับแอดมินเท่านั้น'; end if;
 select campus_id into oldcampus from public.bkg_rooms where id=rid for update;
 if found and oldcampus<>p_data->>'campus_id' then raise exception 'เปลี่ยนศูนย์ของห้องเดิมไม่ได้ ให้สร้างห้องใหม่'; end if;
 insert into public.bkg_rooms(id,campus_id,name,capacity,active,is_sample) values(rid,p_data->>'campus_id',trim(p_data->>'name'),nullif(p_data->>'capacity','')::integer,(p_data->>'active')::boolean,(p_data->>'is_sample')::boolean)
 on conflict(id) do update set name=excluded.name,capacity=excluded.capacity,active=excluded.active,is_sample=excluded.is_sample;return true;
 end;
$$;
create function public.bkg_save_contact(p_data jsonb) returns boolean language plpgsql security definer set search_path='' as $$
 begin
 if not public.bkg_has_scope(null,array['admin']) then raise exception 'สำหรับแอดมินเท่านั้น'; end if;
 if coalesce(length(trim(p_data->>'contact_name')),0)=0 or coalesce(length(trim(p_data->>'contact_phone')),0)=0 then raise exception 'กรุณาระบุชื่อและเบอร์ติดต่อ'; end if;
 update public.bkg_campuses set contact_name=left(trim(p_data->>'contact_name'),200),contact_phone=left(trim(p_data->>'contact_phone'),100) where id=p_data->>'id';return true;
 end;
$$;
create function public.bkg_list_scopes() returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if not public.bkg_has_scope(null,array['admin']) then raise exception 'สำหรับแอดมินเท่านั้น'; end if;
 return(select coalesce(jsonb_agg(to_jsonb(s)-'id'),'[]') from public.bkg_scopes s);
 end;
$$;
create function public.bkg_save_scope(p_data jsonb) returns boolean language plpgsql security definer set search_path='' as $$
 declare uid uuid:=(p_data->>'user_id')::uuid; campus text:=p_data->>'campus_id';
 begin
 if not public.bkg_has_scope(null,array['admin']) then raise exception 'สำหรับแอดมินเท่านั้น'; end if;
 if uid=auth.uid() then raise exception 'แก้สิทธิ์บัญชีตนเองจากหน้านี้ไม่ได้'; end if;
 if p_data->>'role' not in ('staff','head') or campus is null then raise exception 'กำหนดได้เฉพาะเจ้าหน้าที่หรือหัวหน้าในศูนย์'; end if;
 if not exists(select 1 from auth.users where id=uid) then raise exception 'ต้องสร้างบัญชีใน Supabase Authentication ก่อน'; end if;
 delete from public.bkg_scopes where user_id=uid and campus_id=campus;
 if not coalesce((p_data->>'remove')::boolean,false) then insert into public.bkg_scopes(user_id,campus_id,role,name) values(uid,campus,p_data->>'role',coalesce(left(p_data->>'name',200),'')); end if;
 return true;
 end;
$$;
-- Edge Function checks access with the caller's JWT or the per-booking token.
create function public.bkg_file_access(p_id uuid,p_token text default null,p_write boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
 declare b public.bkg_bookings;
 begin
 if not public.bkg_allowed(p_id,p_token) then return false; end if;
 select * into b from public.bkg_bookings where id=p_id;
 return b.kind='booking' and (not p_write or b.status in ('pending','reviewed','approved') and b.starts_at>now());
 end;
$$;
-- Called ONLY by Edge Function service role, with the original caller identity preserved.
create function public.bkg_file_commit(p_booking uuid,p_token text,p_actor uuid,p_file jsonb) returns boolean language plpgsql security definer set search_path='' as $$
 declare b public.bkg_bookings; ok boolean; actor_name text;
 begin
 select * into b from public.bkg_bookings where id=p_booking for update;
 if not found then raise exception 'ไม่พบคำขอ'; end if;
 if p_token is not null then ok:=b.token_hash=encode(extensions.digest(p_token,'sha256'),'hex');actor_name:='ผู้จอง';
 else select exists(select 1 from public.bkg_scopes where user_id=p_actor and (role='admin' or campus_id=b.campus_id)) into ok;select name into actor_name from public.bkg_scopes where user_id=p_actor limit 1;end if;
 if not coalesce(ok,false) or b.kind<>'booking' or b.status not in ('pending','reviewed','approved') or b.starts_at<=now() then raise exception 'ไม่มีสิทธิ์แนบไฟล์ หรือสถานะเปลี่ยนแล้ว'; end if;
 if (select count(*) from public.bkg_attachments where booking_id=p_booking)>=3 then raise exception 'แนบได้สูงสุด 3 ไฟล์'; end if;
 insert into public.bkg_attachments(id,booking_id,name,path,size,mime) values((p_file->>'id')::uuid,p_booking,left(p_file->>'name',255),p_file->>'path',(p_file->>'size')::bigint,p_file->>'mime');
 update public.bkg_bookings set status='pending',reason='' where id=p_booking;
 insert into public.bkg_history(booking_id,actor,actor_id,action) values(p_booking,coalesce(nullif(actor_name,''),'เจ้าหน้าที่'),case when p_token is null then p_actor else null end,'แนบเอกสาร — ส่งกลับรอตรวจสอบ');return true;
 end;
$$;
-- Revoke default execution for every function belonging to this app, not other projects.
do $$ declare f record; begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on p.pronamespace=n.oid where n.nspname='public' and p.proname like 'bkg\_%' escape '\' loop
 execute format('revoke all on function %s from public, anon, authenticated',f.signature);
 end loop;
end $$;
grant execute on function public.bkg_meta(),public.bkg_calendar(text,timestamptz,timestamptz),public.bkg_lookup(text),public.bkg_create(jsonb,uuid,text),public.bkg_detail(uuid,text),public.bkg_edit(uuid,text,text,integer),public.bkg_cancel(uuid,text,text),public.bkg_file_access(uuid,text,boolean) to anon,authenticated;
grant execute on function public.bkg_my_scopes(),public.bkg_staff_list(text),public.bkg_action(uuid,text,text),public.bkg_block(jsonb),public.bkg_save_room(jsonb),public.bkg_save_contact(jsonb),public.bkg_list_scopes(),public.bkg_save_scope(jsonb) to authenticated;
grant execute on function public.bkg_file_commit(uuid,text,uuid,jsonb) to service_role;
-- Private bucket: only the authorized Edge Function can access bytes.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('booking-files','booking-files',false,5242880,array['application/pdf','image/jpeg','image/png']) on conflict(id) do nothing;
reset search_path;
commit;
