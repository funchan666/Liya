update public.liya_curated_video_creators as feature
set display_name = copy.series, caption = copy.caption
from (values
  ('example-video-001', 'Saltwater Notes', 'White water folds against the cliff. There is room in this frame to sit a while.'),
  ('example-video-002', 'The Headland', 'First the walker comes into view. Then the coast seems to open in every direction.'),
  ('example-video-003', 'Passing Weather', 'Through the spray, the trees turn into a blur of green.'),
  ('example-video-004', 'Ridge Walks', 'One bend in the path brings the whole blue lake into view.'),
  ('example-video-005', 'Afterglow', 'A turn of the camera catches orange light under the rock.'),
  ('example-video-006', 'Out for the Evening', 'A table outside, a turn down the street, then the lights come on.'),
  ('example-video-007', 'On the Horizon', 'Above the hikers, a plume rises into a cloudless sky.'),
  ('example-video-008', 'The Slow Route', 'The bikes pass between the pines with the water just beyond them.'),
  ('example-video-009', 'Window Seat', 'From the balcony, the buildings catch the last of the daylight.'),
  ('example-video-010', 'Ice Journal', 'A small boat drifts past ice that changes from white to turquoise.')
) as copy(video_id, series, caption)
where feature.video_id = copy.video_id;

update public.liya_curated_video_prompts as prompt
set display_name = 'Liya', body = copy.body
from (values
  ('example-video-001', 0, 'I kept watching the white line where the waves meet the rock.'),
  ('example-video-001', 1, 'My favorite part was the pause before the camera turned.'),
  ('example-video-002', 0, 'The walker gives the cliffs a sense of scale.'),
  ('example-video-002', 1, 'That thin strip of green above the sea caught my eye.'),
  ('example-video-003', 0, 'The spray makes the whole frame feel cool.'),
  ('example-video-003', 1, 'I like the moment when the trees blur into the background.'),
  ('example-video-004', 0, 'The lake looked even bluer when the trail came into view.'),
  ('example-video-004', 1, 'I would stop at that bend just to take it in.'),
  ('example-video-005', 0, 'That glow changes the way the rock looks.'),
  ('example-video-005', 1, 'I watched again to catch the change in light.'),
  ('example-video-006', 0, 'I like how the daylight gives way to the streetlights.'),
  ('example-video-006', 1, 'The table outside was the detail I remembered.'),
  ('example-video-007', 0, 'I saw the plume before I noticed the hikers.'),
  ('example-video-007', 1, 'The sky stays such a clear blue behind it.'),
  ('example-video-008', 0, 'A slow ride under those pines sounds good today.'),
  ('example-video-008', 1, 'I spotted the water between the trees.'),
  ('example-video-009', 0, 'I liked the last stretch of light over the rooftops.'),
  ('example-video-009', 1, 'Seeing the whole city from one balcony feels strange in a good way.'),
  ('example-video-010', 0, 'The boat makes the ice look enormous.'),
  ('example-video-010', 1, 'I kept looking at the turquoise just below the surface.')
) as copy(video_id, position, body)
where (prompt.video_id, prompt.position) = (copy.video_id, copy.position);
