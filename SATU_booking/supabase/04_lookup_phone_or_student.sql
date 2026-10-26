-- ใช้เมื่อติดตั้ง 01_schema.sql เวอร์ชันก่อนหน้านี้แล้ว
create or replace function public.bkg_lookup(p_phone text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.bkg_rate('lookup',30);
 if length(trim(p_phone))<8 or length(trim(p_phone))>20 then raise exception 'กรุณากรอกเบอร์โทรหรือเลขทะเบียนให้ถูกต้อง'; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'reference',b.reference,'room_id',b.room_id,'campus_id',b.campus_id,'starts_at',b.starts_at,'ends_at',b.ends_at,'status',b.status,'kind',b.kind) order by b.created_at desc),'[]') from public.bkg_bookings b where (b.phone=p_phone or b.student_id=p_phone) and b.kind='booking');
end;
$$;
