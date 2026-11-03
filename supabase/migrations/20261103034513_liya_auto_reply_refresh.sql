-- Expand the server-owned reply library. No client can read or edit it directly.
insert into liya_social_private.liya_reply_library(category, variant, body) values
('hello', 101, 'Hi. I am glad you are here. What has been on your mind lately?'),
('hello', 102, 'Hello! We can start small. How has today felt for you?'),
('hello', 103, 'Hey there. Was there a moment today that stayed with you?'),
('stress', 101, 'That sounds like a lot at once. Which part is taking the most energy today?'),
('stress', 102, 'It is understandable to feel overwhelmed. Is there one thing you can pause for now?'),
('stress', 103, 'That is a heavy list. Would it help to pick the next small step together?'),
('stress', 104, 'You have been carrying quite a bit. What is within reach in the next ten minutes?'),
('sad', 101, 'I am sorry it has been hard. You can tell me as much or as little as you want.'),
('sad', 102, 'That sounds painful. What has been the hardest part of it for you?'),
('sad', 103, 'It is okay to have a difficult day. What might bring a little comfort right now?'),
('sad', 104, 'Thank you for sharing that. Would you rather talk about it or take a small pause?'),
('lonely', 101, 'That kind of distance can feel really heavy. Is there someone you wish you could talk to?'),
('lonely', 102, 'Feeling alone is hard. What kind of connection are you missing most?'),
('lonely', 103, 'Reaching out can take a lot of energy. Is there a trusted person you could send a short hello?'),
('lonely', 104, 'That sounds isolating. Has there been a place or activity where you felt more connected?'),
('happy', 101, 'That sounds like a lovely moment. What made it stand out for you?'),
('happy', 102, 'I am glad something good happened. How did the moment unfold?'),
('happy', 103, 'That is worth celebrating. Who would you most like to share the news with?'),
('happy', 104, 'It sounds like that brought you some joy. What are you looking forward to next?'),
('tired', 101, 'That sounds exhausting. What is one thing you could let wait until tomorrow?'),
('tired', 102, 'A little rest sounds well deserved. Have you had a chance to take a break?'),
('tired', 103, 'It can be hard to think clearly when you are worn out. What would make the next hour easier?'),
('tired', 104, 'You have been doing a lot. Is there a small way to give yourself some breathing room?'),
('relationships', 101, 'That sounds complicated. What would you like this person to understand?'),
('relationships', 102, 'It makes sense to have mixed feelings. What matters most to you in this relationship?'),
('relationships', 103, 'That conversation sounds important. Do you want to think through what you might say?'),
('relationships', 104, 'It can be difficult when expectations differ. What boundary would feel fair to you?'),
('calm', 101, 'If it feels comfortable, try breathing out a little more slowly than you breathe in. How does that feel?'),
('calm', 102, 'You could take a moment to notice the ground beneath your feet. Is there a quieter place nearby?'),
('calm', 103, 'Let us slow things down. Would a glass of water or a short stretch feel manageable?'),
('calm', 104, 'There is no need to solve everything right now. What is one thing you can see around you?'),
('story', 101, 'A little story: on a rainy morning, a neighbor left a warm loaf by the door with a note that said, thought of you. It made an ordinary day feel kinder.'),
('story', 102, 'A little story: a child planted a seed and checked it every day. When a green shoot finally appeared, the whole family gathered to see it.'),
('story', 103, 'A little story: two friends missed the sunset, so they stayed to watch the first stars instead. Neither minded the change of plans.'),
('general', 101, 'I am listening. What part of that would you like to talk about first?'),
('general', 102, 'Thanks for sharing that with me. How has it been feeling for you?'),
('general', 103, 'There is a lot in what you said. What feels most important right now?'),
('general', 104, 'We can take this at your pace. Would you like a question or a little encouragement?'),
('general', 105, 'That sounds like it matters to you. What would you like to happen next?'),
('encourage', 1, 'You do not have to get everything right today. Taking one small step is already something.'),
('encourage', 2, 'A difficult moment does not erase the progress you have made. What is one thing you are proud of?'),
('encourage', 3, 'Here is a little reminder: you are allowed to begin again, even in the middle of the day.'),
('encourage', 4, 'You have made it through every earlier chapter one day at a time. What would help you take the next step?'),
('encourage', 5, 'Be gentle with yourself today. Is there one small thing you can do that feels good?'),
('encourage', 6, 'It is okay to move slowly. Small moments of care still count.'),
('crisis', 101, 'I am sorry you are hurting. If you may act on these thoughts or are in immediate danger, call local emergency services now or go to the nearest emergency department. Please contact someone you trust and ask them to stay with you.'),
('crisis', 102, 'Your safety matters. If you are in immediate danger, contact local emergency services now. If you can, move away from anything you might use to hurt yourself and ask someone you trust to stay with you.')
on conflict (category, variant) do nothing;

-- Keep existing idempotency, owner checks, RLS and free messaging. The reply is
-- selected and stored by the server; visibility is immediate for crisis terms.
create or replace function liya_social_private.auto_send(p_request uuid, p_body text)
returns table(reply_visible_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare
 who uuid := auth.uid(); cleaned text := trim(p_body); category_name text;
 response_text text; total integer; choice integer; due timestamptz; old_body text;
begin
 if who is null then raise exception 'authentication required'; end if;
 if p_request is null or cleaned is null or char_length(cleaned) not between 1 and 2000 then raise exception 'invalid message'; end if;
 perform pg_advisory_xact_lock(hashtextextended(who::text || ':' || p_request::text, 0));
 select m.body into old_body from public.liya_auto_messages m where m.owner_id=who and m.request_id=p_request and m.role='user';
 if found then
  if old_body <> cleaned then raise exception 'request mismatch'; end if;
  return query select m.visible_at from public.liya_auto_messages m where m.owner_id=who and m.request_id=p_request and m.role='assistant';
  return;
 end if;
 category_name := case
  when lower(cleaned) ~ '(suicid|kill myself|end my life|want to die|wanna die|hurt myself|self.harm|自杀|自殺|不想活|想死|伤害自己|傷害自己)' then 'crisis'
  when lower(cleaned) ~ '(lonely|alone|孤独|孤獨|寂寞)' then 'lonely'
  when lower(cleaned) ~ '(anxious|anxiety|stress|overwhelm|压力|壓力|焦虑|焦慮)' then 'stress'
  when lower(cleaned) ~ '(sad|crying|depress|心痛|难过|難過|伤心|傷心)' then 'sad'
  when lower(cleaned) ~ '(tired|exhaust|sleep|疲惫|疲憊|累了)' then 'tired'
  when lower(cleaned) ~ '(friend|partner|family|relationship|朋友|家人|伴侣|伴侶)' then 'relationships'
  when lower(cleaned) ~ '(calm|breathe|relax|平静|平靜|放松|放鬆)' then 'calm'
  when lower(cleaned) ~ '(story|故事)' then 'story'
  when lower(cleaned) ~ '(positive energy|encourage|encouragement|motivat|cheer me|正能量|鼓励|鼓勵)' then 'encourage'
  when lower(cleaned) ~ '(happy|joy|excited|开心|開心|快乐|快樂)' then 'happy'
  when lower(cleaned) ~ '(^|[[:space:],.!])(hi|hello|hey)([[:space:],.!]|$)|你好|嗨' then 'hello'
  else 'general' end;
 select count(*) into total from liya_social_private.liya_reply_library r where r.category=category_name;
 if total = 0 then raise exception 'reply category unavailable'; end if;
 choice := mod(abs(hashtext(p_request::text)::bigint), total)::integer;
 select r.body into response_text from liya_social_private.liya_reply_library r where r.category=category_name order by r.variant offset choice limit 1;
 due := clock_timestamp() + case when category_name = 'crisis' then interval '0 seconds'
  else interval '2 seconds' + mod(abs(hashtext(p_request::text || ':delay')::bigint), 2500) * interval '1 millisecond' end;
 insert into public.liya_auto_messages(owner_id,request_id,role,body,created_at,visible_at) values
  (who,p_request,'user',cleaned,clock_timestamp(),clock_timestamp()),
  (who,p_request,'assistant',response_text,clock_timestamp()+interval '1 millisecond',due);
 return query select due;
end;
$$;
