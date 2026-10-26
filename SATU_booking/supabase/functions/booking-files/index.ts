import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
// Deploy with verify_jwt=false. Every request is authorized with a booking token
// or a VERIFIED Auth user; the service key is never sent to a browser.
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'};
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return json({error:'Method not allowed'},405);
 try{
  if(Number(req.headers.get('content-length')||0)>6*1024*1024)return json({error:'ไฟล์ใหญ่เกินกำหนด'},413);
  const url=Deno.env.get('SUPABASE_URL')!,serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,anonKey=Deno.env.get('SUPABASE_ANON_KEY')!;
  const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const auth=req.headers.get('Authorization');
  const client=createClient(url,anonKey,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:auth?{Authorization:auth}:{}}});
  let payload:any,file:File|null=null;
  if(req.headers.get('content-type')?.includes('multipart/form-data')){const form=await req.formData();payload={action:form.get('action'),id:form.get('id'),token:form.get('token')||null};const part=form.get('file');if(part instanceof File)file=part;}
  else payload=await req.json();
  const {action,id}=payload,token=payload.token||null;
  if(!['list','upload','download'].includes(action)||typeof id!=='string'||! /^[a-f0-9-]{36}$/i.test(id)||token!==null&&(typeof token!=='string'||token.length>128))return json({error:'คำขอไม่ถูกต้อง'},400);
  let actor:string|null=null;
  if(!token){if(!auth)return json({error:'ต้องใช้รหัสจัดการคำขอหรือเข้าสู่ระบบ'},401);const {data,error}=await client.auth.getUser();if(error||!data.user)return json({error:'กรุณาเข้าสู่ระบบใหม่'},401);actor=data.user.id;}
  const {data:allowed,error:accessError}=await client.rpc('bkg_file_access',{p_id:id,p_token:token,p_write:action==='upload'});
  if(accessError||!allowed)return json({error:'ไม่มีสิทธิ์เข้าถึงไฟล์ของคำขอนี้'},403);
  if(action==='list'){const {data,error}=await service.from('bkg_attachments').select('id,name,size,mime').eq('booking_id',id).order('created_at');if(error)throw error;return json(data);}
  if(action==='download'){const {data:f,error}=await service.from('bkg_attachments').select('path,name').eq('booking_id',id).eq('id',payload.fileId).single();if(error||!f)return json({error:'ไม่พบไฟล์'},404);const {data,error:signError}=await service.storage.from('booking-files').createSignedUrl(f.path,60,{download:f.name});if(signError)throw signError;return json({url:data.signedUrl,name:f.name});}
  if(!file||file.size<1||file.size>5242880)return json({error:'กรุณาเลือกไฟล์ไม่เกิน 5 MB'},400);
  const bytes=new Uint8Array(await file.arrayBuffer());
  const isPdf=bytes.length>4&&String.fromCharCode(...bytes.slice(0,5))==='%PDF-';
  const isPng=bytes.length>=8&&[137,80,78,71,13,10,26,10].every((v,i)=>bytes[i]===v);
  const isJpg=bytes.length>3&&bytes[0]===255&&bytes[1]===216&&bytes[2]===255;
  const mime=isPdf?'application/pdf':isPng?'image/png':isJpg?'image/jpeg':null;
  if(!mime||file.type!==mime)return json({error:'รองรับไฟล์ PDF/JPG/PNG ที่ถูกต้องเท่านั้น'},400);
  const {count,error:countError}=await service.from('bkg_attachments').select('id',{count:'exact',head:true}).eq('booking_id',id);if(countError)throw countError;if((count||0)>=3)return json({error:'แนบได้สูงสุด 3 ไฟล์'},400);
  const fid=crypto.randomUUID(),path=id+'/'+fid+(isPdf?'.pdf':isPng?'.png':'.jpg');
  const {error:uploadError}=await service.storage.from('booking-files').upload(path,bytes,{contentType:mime,upsert:false});if(uploadError)throw uploadError;
  const {error:commitError}=await service.rpc('bkg_file_commit',{p_booking:id,p_token:token,p_actor:actor,p_file:{id:fid,path,name:file.name,size:file.size,mime}});
  if(commitError){await service.storage.from('booking-files').remove([path]);return json({error:commitError.message},400);}
  return json({success:true});
 }catch{return json({error:'บริการไฟล์ไม่พร้อม กรุณาตรวจการตั้งค่าหรือลองใหม่'},500);}
});
