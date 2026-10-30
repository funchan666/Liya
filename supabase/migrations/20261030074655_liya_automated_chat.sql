create table liya_social_private.liya_reply_library (
 category text not null, variant integer not null, body text not null,
 primary key(category,variant)
);
revoke all on liya_social_private.liya_reply_library from public,anon,authenticated;
insert into liya_social_private.liya_reply_library(category,variant,body) values
('hello',1,'Hi there. I am glad you stopped by. What has your day been like?'),
('hello',2,'Hello! Take your time settling in. What is on your mind today?'),
('hello',3,'Hey, welcome in. Is there a moment from today you would like to share?'),
('hello',4,'Hi! I am here for a little conversation. How are you feeling right now?'),
('hello',5,'Hello there. We can start anywhere you like, even with something small.'),
('stress',1,'That sounds like a lot to carry at once. What feels most pressing right now?'),
('stress',2,'It makes sense that you feel stretched. Could we choose just one small thing to take care of first?'),
('stress',3,'You do not have to solve the whole week tonight. Is there one thing you can set aside for a moment?'),
('stress',4,'When everything feels loud, a short pause can help. Would you rather talk it through or try a slow breath?'),
('stress',5,'I hear how much is on your plate. What part of this would you most like some space from?'),
('sad',1,'I am sorry this feels so heavy. You do not have to make it sound better here.'),
('sad',2,'That sounds painful. Would you like to tell me what happened, or simply sit with the feeling for a moment?'),
('sad',3,'Some days ask more of us than we have to give. What might be a gentle thing to do for yourself today?'),
('sad',4,'Thank you for putting that into words. Is this a feeling that arrived today or has it been around for a while?'),
('sad',5,'It is okay if you do not have an answer yet. What would feeling a little more supported look like?'),
('lonely',1,'Feeling disconnected can hurt, even in a crowded room. Is there someone you have been missing?'),
('lonely',2,'I am glad you reached out here. Would a small message to someone you trust feel possible today?'),
('lonely',3,'That sounds lonely. What kind of company would feel comforting right now?'),
('lonely',4,'It can take energy to reach out when you feel alone. We can start with what you wish someone understood.'),
('lonely',5,'You deserve connection that feels safe and mutual. Has anything helped you feel closer to others before?'),
('happy',1,'I love hearing that something went well. What was your favorite part of it?'),
('happy',2,'That sounds like a bright moment. Want to tell me how it happened?'),
('happy',3,'Let us give that moment a little room. What made it feel special to you?'),
('happy',4,'That is lovely to hear. Is this something you had been looking forward to?'),
('happy',5,'A good moment is worth noticing. How are you going to remember this one?'),
('tired',1,'It sounds like you have been running low. Is there a small way you could rest today?'),
('tired',2,'Being tired can make everything feel harder. Have you had a chance to pause or eat something?'),
('tired',3,'You do not need to earn a break. What would a realistic bit of rest look like right now?'),
('tired',4,'That sounds draining. Is it more your body, your thoughts, or a little of both?'),
('tired',5,'It is okay to move more slowly. What is one thing that could wait until later?'),
('relationships',1,'Relationships can bring up a lot at once. What part of this feels hardest to say?'),
('relationships',2,'It sounds like this person matters to you. What do you wish they understood about your side?'),
('relationships',3,'There may be more than one feeling here. What are you hoping will happen next?'),
('relationships',4,'That sounds complicated. Would it help to think through what you want to communicate?'),
('relationships',5,'You can care about someone and still need boundaries. What feels important for you to protect?'),
('calm',1,'Try letting your shoulders soften, then breathe out slowly. What do you notice around you?'),
('calm',2,'If it feels comfortable, take one unhurried breath. We can go one moment at a time.'),
('calm',3,'A small pause might help: name one thing you can see and one thing you can feel beneath your feet.'),
('calm',4,'Let us make this moment a little quieter. Would a breath, a stretch, or some water feel right?'),
('calm',5,'You can slow down without needing to make the feeling disappear. What feels grounding for you?'),
('story',1,'A tiny story: a person left a lamp on for a friend who was running late. Neither said much when they arrived, but the warm light did the welcoming.'),
('story',2,'A tiny story: a seedling bent toward a window each morning. Nobody rushed it; they simply kept making room for the light.'),
('story',3,'A tiny story: two neighbors kept leaving notes about the weather. One rainy day, one note said, I hope your tea is warm. The other smiled.'),
('story',4,'A tiny story: someone found a smooth stone on a difficult walk and kept it as a reminder that even rough paths can hold small treasures.'),
('story',5,'A tiny story: a baker saved the last warm roll for a stranger. It did not fix the stranger’s day, but it made the next ten minutes kinder.'),
('general',1,'I am listening. What part of that feels most important to you right now?'),
('general',2,'Thank you for sharing that. What would you like to explore a little more?'),
('general',3,'There is room for whatever you are feeling. Where would you like to begin?'),
('general',4,'I hear you. Would you like a thoughtful question, or a little encouragement?'),
('general',5,'We can take this one step at a time. What is the next small thing on your mind?'),
('general',6,'That sounds meaningful to you. Can you tell me a little more about it?'),
('general',7,'I am here for this conversation. What would feel helpful to talk about next?'),
('general',8,'There is no rush to have it all figured out. What stands out most in this moment?'),
('crisis',1,'I am sorry you are in so much pain. If you might act on these thoughts or are in immediate danger, call local emergency services now or go to the nearest emergency department. Please reach out to someone you trust and ask them to stay with you.'),
('crisis',2,'You deserve immediate support. If you may be in danger, contact local emergency services now. If you can, move away from anything you could use to hurt yourself and tell a trusted person you need them with you.'),
('crisis',3,'I am concerned about your safety. Please contact local emergency services if there is immediate danger, and reach out to a trusted person who can stay with you. You do not have to face this alone.');
create table public.liya_auto_messages (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null, role text not null check(role in ('user','assistant')),
 body text not null check(char_length(body) between 1 and 3000),
 created_at timestamptz not null default now(), visible_at timestamptz not null default now(),
 unique(owner_id,request_id,role)
);
create index liya_auto_messages_owner_time on public.liya_auto_messages(owner_id,created_at,id);
alter table public.liya_auto_messages enable row level security;
revoke all on public.liya_auto_messages from public,anon,authenticated;
grant select on public.liya_auto_messages to authenticated;
create policy liya_auto_messages_read on public.liya_auto_messages for select to authenticated using(owner_id=(select auth.uid()) and visible_at<=now());
create function liya_social_private.auto_send(p_request uuid,p_body text) returns table(reply_visible_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare who uuid := auth.uid(); cleaned text := trim(p_body); category_name text; response_text text; total integer; choice integer; due timestamptz; old_body text;
begin
 if who is null then raise exception 'authentication required'; end if;
 if p_request is null or cleaned is null or char_length(cleaned) not between 1 and 2000 then raise exception 'invalid message'; end if;
 perform pg_advisory_xact_lock(hashtextextended(who::text || ':' || p_request::text,0));
 select m.body into old_body from public.liya_auto_messages m where m.owner_id=who and m.request_id=p_request and m.role='user';
 if found then
  if old_body<>cleaned then raise exception 'request mismatch'; end if;
  return query select m.visible_at from public.liya_auto_messages m where m.owner_id=who and m.request_id=p_request and m.role='assistant';
  return;
 end if;
 category_name := case
  when lower(cleaned) ~ '(suicid|kill myself|end my life|hurt myself|self.harm|自杀|自殺|不想活|伤害自己|傷害自己)' then 'crisis'
  when lower(cleaned) ~ '(lonely|alone|孤独|孤獨|寂寞)' then 'lonely'
  when lower(cleaned) ~ '(anxious|anxiety|stress|overwhelm|压力|壓力|焦虑|焦慮)' then 'stress'
  when lower(cleaned) ~ '(sad|crying|depress|心痛|难过|難過|伤心|傷心)' then 'sad'
  when lower(cleaned) ~ '(tired|exhaust|sleep|疲惫|疲憊|累了)' then 'tired'
  when lower(cleaned) ~ '(friend|partner|family|relationship|朋友|家人|伴侣|伴侶)' then 'relationships'
  when lower(cleaned) ~ '(calm|breathe|relax|平静|平靜|放松|放鬆)' then 'calm'
  when lower(cleaned) ~ '(story|故事)' then 'story'
  when lower(cleaned) ~ '(happy|joy|excited|开心|開心|快乐|快樂)' then 'happy'
  when lower(cleaned) ~ '(^|[[:space:],.!])(hi|hello|hey)([[:space:],.!]|$)|你好|嗨' then 'hello'
  else 'general' end;
 select count(*) into total from liya_social_private.liya_reply_library r where r.category=category_name;
 choice := mod(abs(hashtext(p_request::text)::bigint),total)::integer;
 select r.body into response_text from liya_social_private.liya_reply_library r where r.category=category_name order by r.variant offset choice limit 1;
 due := clock_timestamp() + interval '3 seconds';
 insert into public.liya_auto_messages(owner_id,request_id,role,body,created_at,visible_at) values
 (who,p_request,'user',cleaned,clock_timestamp(),clock_timestamp()),
 (who,p_request,'assistant',response_text,clock_timestamp()+interval '1 millisecond',due);
 return query select due;
end;
$$;
revoke all on function liya_social_private.auto_send(uuid,text) from public,anon,authenticated;
grant execute on function liya_social_private.auto_send(uuid,text) to authenticated;
create function public.liya_auto_send(p_request uuid,p_body text) returns table(reply_visible_at timestamptz)
language sql security invoker set search_path='' as $$ select * from liya_social_private.auto_send(p_request,p_body); $$;
revoke all on function public.liya_auto_send(uuid,text) from public,anon,authenticated;
grant execute on function public.liya_auto_send(uuid,text) to authenticated;
