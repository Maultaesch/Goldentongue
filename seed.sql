insert into public.challenges (text, skill, difficulty) values
 ('Start a conversation with one stranger.', 'confidence', 1),
 ('Give one sincere compliment about a choice, not looks.', 'flirting', 1),
 ('Hold a five-minute conversation.', 'communication', 2),
 ('Ask someone about their day and follow up once.', 'communication', 1),
 ('Introduce yourself to a new colleague.', 'business', 1),
 ('Say your pitch aloud three times.', 'articulation', 1)
on conflict (text) do nothing;

insert into public.lines (category, text, popularity) values
 ('opener', 'Hi, I''m [name]. I don''t think we''ve met yet.', 80),
 ('opener', 'Great venue. Have you been here before?', 70),
 ('opener', 'Quick question: what''s the best spot nearby?', 30),
 ('flirting', 'I bet you have strong opinions about pizza toppings.', 75),
 ('flirting', 'You have a great laugh. What''s the story behind it?', 40),
 ('flow', 'What got you into that?', 85),
 ('flow', 'Tell me more about that.', 60),
 ('attraction', 'Ask one question about their passion, then listen.', 70),
 ('attraction', 'If it''s a no, say thank you and leave kindly.', 55);
